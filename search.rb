# This script accepts an email address to use to retrieve an Amazon wishlist
# for, and an optional branch-ID for the Chicago Public Library system. The
# script parses the wishlist and finds the books that are available for
# *CHECK OUT* (unavailable books, in-transit, on hold, etc. are ignored).

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

# for printing to term, ANSI color, windows support = ?
ORANGE_COLOR = "\033[33m"
CLEAR_COLOR  = "\033[0m"

# loop through the pages of the wishlist,
# on the first time through after we receive the first page, we'll grab the
# maximum number of pages
def get_wishlist(email)
  books = []

  puts "Retrieving wishlist"

  # attempt to retrieve the wishlist
  uri = URI.parse("http://www.amazon.com/registry/search.html?type=wishlist&field-name=#{email}")
  uri_path = "#{uri.path}?#{uri.query}"
  request = Net::HTTP::Get.new(uri_path)
  response = Net::HTTP.start(uri.host, uri.port) do |http|
    http.request(request)
  end
  wishlist_url = response['location']

  if wishlist_url.nil?
    puts "Cannot find the wishlist for #{email}"
    exit
  end

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
      books.push({ :title => title, :isbn => isbn })

      # right now, I'm not using author:
      next

      # grab the author, eliminating the " by " text if it exists,
      # also eliminate the special characters
      authors = part.css('span[class="tiny"]').first.text.gsub(/\s*by\s+/, '').match(/([\w\s\'\-\.]+)/)
      if authors and not authors.captures.empty?
        # temporarily use the first author
        books.push({ :author => authors.captures.first.strip, :title => title, :isbn => isbn })
      end
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
      if LIBRARY_BRANCH_LOCATION != nil && tablerow.previous_sibling.to_s.index("Your Library") != nil 
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
def find_books(books, library)
  puts "Finding books..."
  book_available = false

  books.each do |book|
    # get related isbns and limit collection to a maximum of 10 ISBNs
    related_isbns = get_related_isbns(book[:isbn])[0...10]

    libraries_available = []
    # search through ISBNs, 5 at a time (due to limits on chipublib search),
    # break at first results found
    (0...related_isbns.length).step(5) do |count|
      isbn_search_range = related_isbns[count...count+5]
      isbn_search_string = isbn_search_range.join('+or+')

      fetch_result = fetch("#{LIBRARY_SEARCH_URL}?&isbn=#{isbn_search_string}&location=#{LIBRARY_BRANCH_LOCATION}&format=Book&advancedSearch=submitted")

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
      # sleep 1/10
    end

    # show where the book is available, if it isn't available, output nothing
    if libraries_available.include? LIBRARY_MY_STRING
      book_available = true
      puts "#{ORANGE_COLOR}#{book[:title]}#{CLEAR_COLOR} is available at your library."
    elsif libraries_available.length > 0 && LIBRARY_BRANCH_LOCATION == ''
      book_available = true
      puts "#{ORANGE_COLOR}#{book[:title]}#{CLEAR_COLOR} is available at: #{libraries_available.uniq.join(', ')}"
    else
      # puts "#{book[:title]} is not available."
    end
  end

  puts "No books available" unless book_available == true
end

# usage:
unless ARGV.length == 1 || ARGV.length == 2
  puts "Usage: #{$0} [email] [library-id]"
  puts "Library id can be left blank, otherwise an id is needed corresponding to"
  puts "the library you want, example: 70 for Chinatown, 320 for Bucktown-Wicker park"
  puts "defaults to Bucktown-Wicker Park (ids are from chipublib.org's catalog search)"
  exit
end

email = ARGV[0]

# second arg not specified?
case ARGV[1]
when nil then library = ''
else library = ARGV[1]
end

LIBRARY_BRANCH_LOCATION = library

# TODO:
# Sinatra-fy into heroku app so I can use on my phone
# - due to the many requests that need to be made, 
# - combined with the scraping/parsing,
# - it is probably too slow to be useful

books = get_wishlist(email)
find_books(books, library)
