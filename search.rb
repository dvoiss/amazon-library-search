require 'net/https'
require "open-uri"
require 'uri'
require 'zlib'

require "nokogiri"

# the library thing isbn api allows us to get related ISBNs,
# so if we're searching for a book and the library has an older or newer
# edition or a reprint, etc. we can search for that as well
LIBRARY_THING_ISBN_URL = "http://www.librarything.com/api/thingISBN/"

# library constants
LIBRARY_BASE_URL = "http://www.chipublib.org"
LIBRARY_SEARCH_URL = "#{LIBRARY_BASE_URL}/search/results/"
LIBRARY_REFERER_URL = "#{LIBRARY_BASE_URL}/search/advanced/"
LIBRARY_NO_RESULTS_STRING = "Your search did not produce any results."
LIBRARY_MY_STRING = "My Library"
LIBRARY_NOT_CHECKED_OUT = "Not checked out"

@@library_branch_location = ''

# loop through the items of the wishlist,
# compact wishlists are 1 page?
def get_wishlist(email, stream)
  books = []

  # attempt to retrieve the wishlist
  uri = URI.parse("http://www.amazon.com/registry/search.html?type=wishlist&field-name=#{email}")
  uri_path = "#{uri.path}?#{uri.query}"
  request = Net::HTTP::Get.new(uri_path)
  response = Net::HTTP.start(uri.host, uri.port) do |http|
    http.request(request)
  end
  wishlist_url = response['location']

  if wishlist_url.nil?
    stream << "data: status: Cannot find the wishlist for #{email}\n\n"
    stream << "data: #{nil}\n\n"
    stream.flush
    return
  else
    stream << "data: status: Found the wishlist for #{email}\n\n"
  end

  # the filter=3 is filter by books
  page = Nokogiri::HTML(open("#{wishlist_url}&filter=3&layout=compact"))
  # get the divs and parse out their title and author
  page.css('tbody[class=itemWrapper]').each do |part|
    link_with_isbn = part.css('span[class="small productTitle"] a')
    link = link_with_isbn.length > 0 ? link_with_isbn.first : nil
    if link.nil?; next end

    # get the href attribute and try to get a match for the ISBN
    isbn_available = link.attr('href').match(/dp\/([\d\w]+)\//)
    # did we get an ISBN?
    if isbn_available && isbn_available.captures.one?
      isbn = isbn_available.captures.pop
      title = link_with_isbn.text.strip
      books.push({ :title => title, :isbn => isbn, :url => link.attr('href') })
    end
  end

  books
end

# for fetching the library pages
def fetch(uri_str, limit = 5, page_type = "search")
  if limit > 0
    uri = URI.parse(uri_str)

    # header
    header = {
      "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_2) AppleWebKit/535.7 (KHTML, like Gecko) Chrome/16.0.912.75 Safari/535.7",
      "Referer" => LIBRARY_REFERER_URL,
      "Host" => uri.host,
      "Accept-Encoding" => "gzip,deflate,sdch"
    }

    # reference: http://ruby-doc.org/stdlib/libdoc/net/http/rdoc/classes/Net/HTTP.html
    request = Net::HTTP::Get.new(uri.request_uri)
    request.initialize_http_header(header)
    response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
    case response
    when Net::HTTPSuccess     then { :response => response, :page_type => page_type }
    when Net::HTTPRedirection then fetch("#{LIBRARY_BASE_URL + response['location']}", limit - 1, "detail")
    else
      response.error!
    end
  else
    # todo
    raise "TOO MANY REDIRECTS"
  end
end

# use librarything's ISBN api to retrieve related ISBNs,
# so we don't miss the book we want because of a reprint or different edition,
# one book can have many ISBNs as a result of different versions, etc.
def get_related_isbns(isbn)
  response = open("http://www.librarything.com/api/thingISBN/" + isbn)
  if response.nil?; return [isbn] end

  page = Nokogiri::XML(response)
  related_isbns = []
  page.css('isbn').each { |related_isbn| related_isbns.push(related_isbn.text) }

  related_isbns
end

# parse a "detail page" (page which results when a book has been found)
def parse_detail(body)
  libraries = []

  page = Nokogiri::HTML(body)
  page.css('table[class=summary] tr').each do |tablerow|
    if tablerow.to_s.index(LIBRARY_NOT_CHECKED_OUT) != nil
      # it's at our library, break out of loop
      if @@library_branch_location != nil && tablerow.previous_sibling.to_s.index("Your Library") != nil 
        return [LIBRARY_MY_STRING]
      end

      # it isn't checked out at this location, save library name
      libraries.push tablerow.css('td').first.text
    end
  end

  libraries
end

# parse the "search results page"
# get the libraries the book is available at, if it is available at the library
# specified by LIBRARY_MY_STRING, then just return that library
def parse_search_results(page)
  libraries_available = []
  links = page.css("ol[class=result] li[class=clearfix] h3 a")
  links.each do |link|
    fetch_result = fetch("#{LIBRARY_BASE_URL + (link.attr 'href')}")
    body = Zlib::GzipReader.new(StringIO.new(fetch_result[:response].body)).read
    libraries_available.concat parse_detail(body)

    # should we go to the next link? do we already know if it's available at our library?
    if libraries_available.include? LIBRARY_MY_STRING; return [LIBRARY_MY_STRING] end
  end

  libraries_available
end

# go through books and tell me if they are available at my local library
def find_books(books, library, stream)
  @@library_branch_location = library
  stream << "data: status: Finding which books are available...\n\n"
  book_available = false

  books.each do |book|
    # get related isbns and limit collection to a maximum of 20 ISBNs
    related_isbns = get_related_isbns(book[:isbn])[0...20]

    libraries_available = []
    # search through ISBNs, 5 at a time (due to limits on chipublib search),
    # break at first results found
    (0...related_isbns.length).step(5) do |count|
      isbn_search_range = related_isbns[count...count+5]
      isbn_search_string = isbn_search_range.join('+or+')

      fetch_result = fetch("#{LIBRARY_SEARCH_URL}?&isbn=#{isbn_search_string}&location=#{@@library_branch_location}&format=Book&advancedSearch=submitted")

      # unzip
      body = Zlib::GzipReader.new(StringIO.new(fetch_result[:response].body)).read

      if fetch_result[:page_type] == "search"
        if body.index(LIBRARY_NO_RESULTS_STRING) == nil
          # assemble a collection of results
          page = Nokogiri::HTML(body)
          libraries_available = parse_search_results(page)
        else
          # no results for this book's ISBN(s)
          # puts LIBRARY_NO_RESULTS_STRING
        end
      else # detail, one result for this book's ISBN(s)
        libraries_available = parse_detail(body)
      end

      # if it's available at our library, don't bother going through any other ISBNs for this book,
      # just tell me it's available so the next book can be processed
      if libraries_available.include? LIBRARY_MY_STRING; break end

      # don't make too many requests too fast :)
      sleep 1/60
    end

    # show where the book is available
    html = "<li><a href='#{book[:url]}' title='#{book[:title]}'>#{book[:title]}</a> is available"
    if libraries_available.include? LIBRARY_MY_STRING
      book_available = true
      stream << "data: #{html}\n\n"
    elsif libraries_available.length > 0 && @@library_branch_location == ''
      book_available = true
      html += " at "
      libraries_available.uniq.each do |library|
        html += "<span class='library'>#{library}</span>"
        if (libraries_available.last != library); html += ", " end
      end
      html += "</li>"
      stream << "data: #{html}\n\n"
    else
      # show those unavailable
    end

  end

  stream << "data: status: None of your books are available.\n\n" unless book_available == true
end