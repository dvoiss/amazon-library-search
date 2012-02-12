require "nokogiri"
require "open-uri"

# books filter id
BOOKS = 3
#BASE_URL = "http://www.amazon.com/gp/registry/wishlist/"
BASE_AMAZON_URL = "http://www.amazon.com/registry/wishlist/"
URL = BASE_AMAZON_URL + "DB9C2V4SS2YQ" + "/?reveal=unpurchased&filter=#{BOOKS}&sort=date-added&layout=compact&x=9&y=1"

LIBRARY_THING_ISBN_URL = "http://www.librarything.com/api/thingISBN/"

LIBRARY_BASE_URL = "http://www.chipublib.org"
LIBRARY_SEARCH_URL = "http://www.chipublib.org/search/results/"
LIBRARY_REFERER_URL = "http://www.chipublib.org/search/advanced/"
LIBRARY_ERROR_STRING = "Your search did not produce any results."

page_num = 1
max_page_num = 0

books = []

# loop through the pages of the wishlist,
# on the first time through after we receive the first page, we'll grab the
# maximum number of pages
loop do
  page = Nokogiri::HTML(open("#{URL}&page=#{page_num.to_s}"))

  if max_page_num == 0
    max_page_num = page.css('table[class=sortbarTopTable] span[class=num-pages]').text.to_i
  end

  puts "Retrieved page #{page_num.to_s}" + 
    (max_page_num > 0 ? " of #{max_page_num.to_s}" : "")

  # get the divs and parse out their title and author
  book_parts = page.css('tbody[class=itemWrapper]')
  File.open("test_file.html", "w") { |somefile| somefile.puts page }
  for part in book_parts
    link_with_isbn = part.css('span[class="small productTitle"] a')
    link = 0
    if link_with_isbn.respond_to? 'first'
      link = link_with_isbn.first
    end

    url = link.attr 'href'
    isbn_available = url.match(/dp\/([\d\w]+)\//)

    if isbn_available && isbn_available.captures.one?
      isbn = isbn_available.captures.pop
      title = part.css('span[class="small productTitle"] a').text
      books.push({ :title => title, :isbn => isbn })

      # right now, not using author:
      next
      # grab the author, eliminating the " by " text,
      # also eliminate the special characters
      authors = part.css('span[class="tiny"]').first.text.gsub(/\s*by\s+/, '').match(/([\w\s\'\-\.]+)/)
      if authors && authors.captures
        books.push({ :author => authors.captures.first.strip, :title => title, :isbn => isbn })
      end
    end
  end

  page_num = page_num + 1
  if page_num > max_page_num
    break
  end

  # don't make too many requests too fast :)
  sleep 1/10
end

require 'cgi'
require 'uri'
require 'net/https'
require 'zlib'

def fetch(uri_str, limit = 5, page_type = "search")
  if limit > 0
    uri = URI.parse(uri_str)

    # user-agent
    ua = {
      "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_2) AppleWebKit/535.7 (KHTML, like Gecko) Chrome/16.0.912.75 Safari/535.7",
      "Referer" => LIBRARY_REFERER_URL,
      "Host" => uri.host,
      "Accept-Encoding" => "gzip,deflate,sdch"
    }

    # reference: http://ruby-doc.org/stdlib/libdoc/net/http/rdoc/classes/Net/HTTP.html
    request = Net::HTTP::Get.new(uri.request_uri)
    request.initialize_http_header(ua)
    response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
    case response
    when Net::HTTPSuccess     then { :response => response, :page_type => page_type }
    when Net::HTTPRedirection then puts "REDIRECT #{response['location']}"; fetch("#{LIBRARY_BASE_URL + response['location']}", limit - 1, "detail")
    else
      response.error!
    end
  else
    "TOO MANY REDIRECTS"
  end
end

# use librarything's ISBN api to retrieve related ISBNs,
# so we don't miss the book we want because of a reprint or different edition,
# one book can have many ISBNs as a result of different versions, etc.
def get_related_isbns(isbn)
  related_isbns = []
  page = Nokogiri::XML(open("http://www.librarything.com/api/thingISBN/" + isbn))
  page.xpath('//isbn').each do |related_isbn|
    related_isbns.push(related_isbn.text)
  end

  related_isbns
end

BRANCH_LOCATION = 320
NOT_CHECKED_OUT = "Not checked out"

def parse_detail(body)
  page = Nokogiri::HTML(body)
  libraries = []
  page.css('table[class=summary] tr').each do |tablerow|
    if tablerow.to_s.index(NOT_CHECKED_OUT) != nil
      # it's at our library, break out of loop
      if BRANCH_LOCATION != nil && tablerow.previous_sibling.to_s.index("Your Library") != nil 
        libraries.push "My Library"
        break
      end

      # it isn't checked out at this location, save library name
      libraries.push tablerow.css('td').first.text
    end
  end

  libraries
end

def available_at(page)
  libraries_available = []
  links = page.css("ol[class=result] li[class=clearfix] h3 a")
  links.each do |link|
    fetch_result = fetch("#{LIBRARY_BASE_URL + (link.attr 'href')}")
    body = Zlib::GzipReader.new(StringIO.new(fetch_result[:response].body)).read
    libraries_available.concat parse_detail(body)

    # should we go to the next link? do we already know if it's available at our library?
    if libraries_available.include? "My Library"; break end
  end

  libraries_available
end

# go through books
books.each do |book|
  successful_find = true

  # get related isbns and limit collection to a maximum of 10 ISBNs
  related_isbns = get_related_isbns(book[:isbn])[0...10]
  # search through ISBNs, 5 at a time (due to limits on chipublib search),
  # break at first results found
  (0...related_isbns.length).step(5) do |count|
    isbn_search_range = related_isbns[count...count+5]
    isbn_search_string = isbn_search_range.join('+or+')

    fetch_result = fetch(
      "#{LIBRARY_SEARCH_URL}?keywords=&title=&isbn=#{isbn_search_string}&location=#{BRANCH_LOCATION}&format=Book&advancedSearch=submitted"
    )

    # unzip
    body = Zlib::GzipReader.new(StringIO.new(fetch_result[:response].body)).read

    libraries_available = []
    if fetch_result[:page_type] == "search"
      if body.index(LIBRARY_ERROR_STRING) == nil
        # assemble a collection of results
        page = Nokogiri::HTML(body)
        libraries_available = available_at(page)
      else
        # puts LIBRARY_ERROR_STRING
      end
    else # detail
      libraries_available = parse_detail(body)
    end

    if not libraries_available.empty?
      puts book[:title], libraries_available.uniq.to_s
      break
    end

    sleep 1/10
  end
end
