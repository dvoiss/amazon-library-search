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
LIBRARY_BASE_URL               = "http://www.chipublib.org"
LIBRARY_SEARCH_URL             = "#{LIBRARY_BASE_URL}/search/results/"
LIBRARY_REFERER_URL            = "#{LIBRARY_BASE_URL}/search/advanced/"
LIBRARY_NO_RESULTS_STRING      = "Your search did not produce any results."
LIBRARY_MY_STRING              = "My Library"
LIBRARY_NOT_CHECKED_OUT_STRING = "Not checked out"

# holds the library name
@library_branch_location = ''

# Public: Finds the wishlist and if found, loops through the items 
# on it putting them into a collection.
#
# email  - The email address to be used in the amazon URL.
# stream - Sinatra::Helpers::Stream, used for sending messages to the client.
#
# Returns nil of no wishlist is found, else returns the list of wishlist items.
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
  page = Nokogiri::HTML(open("#{wishlist_url}&layout=compact"))
  # get the divs and parse out their title and author
  page.css('tbody[class=itemWrapper]').each do |part|
    link_with_isbn = part.css('span[class="small productTitle"] a')
    link = link_with_isbn.length > 0 ? link_with_isbn.first : nil
    next if link.nil?

    url = link.attr('href')
    # get the href attribute and try to get a match for the ISBN
    isbn_available = url.match(/dp\/([\d\w]+)\//)
    # may match non-book items (which won't affect the program however)
    isbn_available = url.match(/gp\/product\/([\d\w]+)[\/\?]/) if !isbn_available
    
    # did we get an ISBN?
    if isbn_available && isbn_available.captures.one?
      isbn = isbn_available.captures.pop
      title = link_with_isbn.text.strip
      books.push({ :title => title, :isbn => isbn, :url => url })
    end
  end

  books
end
 
# Public: Fetches the library pages.
#
# uri_str        - A string that is the URL to be fetched.
# redirect_limit - The number of redirects to allow, defaults to 5.
# page_type      - The type of library page being fetched (defaults to a "search" page).
#
# Returns a hash with the response object and the type of page it is returning (search or detail).
def fetch(uri_str, limit = 5, page_type = "search")
  if limit > 0
    uri = URI.parse(uri_str)

    # header
    header = {
      "User-Agent"      => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_2) AppleWebKit/535.7 (KHTML, like Gecko) Chrome/16.0.912.75 Safari/535.7",
      "Referer"         => LIBRARY_REFERER_URL,
      "Host"            => uri.host,
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
    raise "TOO MANY REDIRECTS"
  end
end

# Public: Gets the ISBNs related to a given ISBN from Library Thing's API.
# Getting related ISBNs is necessary because different print runs, editions,
# publishers, etc. can result in different ISBNs for the same book.
#
# isbn - The ISBN to send to the API.
#
# Returns a collection of ISBNs.
def get_related_isbns(isbn)
  response = open(LIBRARY_THING_ISBN_URL + isbn)
  return [isbn] if response.nil?

  page = Nokogiri::XML(response)
  related_isbns = []
  page.css('isbn').each { |related_isbn| related_isbns.push(related_isbn.text) }

  related_isbns
end

# Public: Parses a "detail" page entry. A "detail" page is when the library has found
# a given book. Nokogiri parses the page to find whether the book is available.
#
# page - The page to be parsed by Nokogiri.
#
# Returns a collection of libraries that have the book, or returns the string LIBRARY_MY_STRING
# if the book has been found at the user specified library.
def parse_detail(page)
  libraries = []

  body = Nokogiri::HTML(page)
  body.css('table[class=summary] tr').each do |tablerow|
    # does the tablerow contain the "not checked out" string?
    # I don't want "reference" material that can't be checked out
    if tablerow.to_s.include?(LIBRARY_NOT_CHECKED_OUT_STRING) && !tablerow.to_s.include?("Reference")
      # if it's at our library, return
      return [LIBRARY_MY_STRING] if @library_branch_location && tablerow.to_s.include?(@library_branch_location)

      # it isn't checked out at this location, save library name
      libraries.push tablerow.css('td').first.text
    end
  end

  libraries
end

# Public: Parses a "search" page. A "search" page is when the library has returned a
# page listing the found books. We fetch each found book and send to parse_detail.
#
# page - The page to be parsed by Nokogiri.
#
# Returns a collection of libraries that have the book, or returns the string LIBRARY_MY_STRING
# if the book has been found at the user specified library.
def parse_search_results(page)
  libraries_available = []

  body = Nokogiri::HTML(page)
  links = body.css("ol[class=result] li[class=clearfix] h3 a")
  links.each do |link|
    fetch_result = fetch("#{LIBRARY_BASE_URL + (link.attr 'href')}")
    response_body = Zlib::GzipReader.new(StringIO.new(fetch_result[:response].body)).read
    libraries_available.concat parse_detail(response_body)

    # should we go to the next link? do we already know if it's available at our library?
    return [LIBRARY_MY_STRING] if libraries_available.include? LIBRARY_MY_STRING
  end

  libraries_available
end

# Public: Go through the list of retrieved books, stream results to the client when 
# books are found.
#
# books            - The list of books to search through.
# library_code     - The code of the library to be used in the URL.
# library_location - The name of the library.
# stream           - Sinatra::Helpers::Stream, used for sending messages to the client.
def find_books(books, library_code, library_location, stream)
  # special cases for library_location:
  if library_location == "Harold Washington Library Center"
    @library_branch_location = "HWLC"
  else
    @library_branch_location = library_location == "Any Library" ? nil : library_location
  end

  book_available = false
  stream << "data: status: Finding which books are available...\n\n"

  books.each do |book|
    # get related isbns and limit collection to a maximum # of ISBNs
    related_isbns = get_related_isbns(book[:isbn])[0...15]

    libraries_available = []
    # search through ISBNs, 5 at a time (due to limits on chipublib search),
    # break at first results found
    (0...related_isbns.length).step(5) do |count|
      isbn_search_range = related_isbns[count...count+5]
      isbn_search_string = isbn_search_range.join('+or+')

      fetch_result = fetch("#{LIBRARY_SEARCH_URL}?&isbn=#{isbn_search_string}&location=#{library_code}&format=Book&advancedSearch=submitted")

      # unzip
      response_body = Zlib::GzipReader.new(StringIO.new(fetch_result[:response].body)).read

      # if it's a search page, parse the search results,
      # else it's a detail, parse the detail page
      if fetch_result[:page_type] == "search"
        if !response_body.include?(LIBRARY_NO_RESULTS_STRING)
          libraries_available.concat parse_search_results(response_body)
        end
      else
        libraries_available.concat parse_detail(response_body)
      end

      # if it's available at our library, don't bother going through any other ISBNs for this book,
      # just tell me it's available so the next book can be processed
      break if libraries_available.include? LIBRARY_MY_STRING

      # don't make too many requests too fast :)
      sleep 1/60
    end

    # show where the book is available
    html = %(<li><a href="#{book[:url]}" title="#{book[:title]}">#{book[:title]}</a>)
    if libraries_available.include? LIBRARY_MY_STRING
      book_available = true
      stream << "data: #{html}</li>\n\n"
    elsif libraries_available.length > 0 && @library_branch_location.nil?
      book_available = true
      html += " is available at "
      libraries_available.uniq.each do |library|
        html += %(<span class="library">#{library}</span>)
        html += ", " if (libraries_available.uniq.last != library)
      end
      html += "</li>"
      stream << "data: #{html}\n\n"
    end

  end

  stream << "data: status: None of your books are available.\n\n" unless book_available == true
end