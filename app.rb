require "nokogiri"
require "open-uri"

# books filter id
BOOKS = 3
#BASE_URL = "http://www.amazon.com/gp/registry/wishlist/"
BASE_URL = "http://www.amazon.com/registry/wishlist/"
URL = BASE_URL + "DB9C2V4SS2YQ" + "/?reveal=unpurchased&filter=#{BOOKS}&sort=date-added&layout=compact&x=9&y=1"

LIBRARY_THING_ISBN_URL = "http://www.librarything.com/api/thingISBN/"

BRANCH_ID = 320
LIBRARY_SEARCH_URL = "http://www.chipublib.org/search/results/"
LIBRARY_REFERER_URL = "http://www.chipublib.org/search/advanced/"

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

  puts "Attempting to retrieve page #{page_num.to_s}" + 
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
      authors = part.css('span[class="tiny"]').first.text.gsub(/\s*by\s+/, '').match(/([\w\s\'\-\.]+)/) #gsub(/\s+\(Author\)\s+/, '')
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
puts books

=begin
title_string = "&title="
iter = 0
for title in books
  if iter != 0
    title_string += '+or+'
  end
  title_string = title_string + '"' + title.gsub(/[^\w\s]/, '').gsub(/\s+/, '+') + '"'
  iter = iter + 1
end

author_string = "&author="
iter = 0
for author in authors
  if iter != 0
    author_string += '+or+'
  end
  # build string, eliminating special characters and collapsing white space down to '+'
  author_string = author_string + author.gsub(/[^\w\s]/, '').gsub(/\s+/, '+')
  iter = iter + 1
end
=end

require 'cgi'
require 'uri'
require 'net/https'
require 'zlib'

def inflate(body)
  #zstream = Zlib::Inflate.new
  #buf = zstream.inflate(body)
  gz = Zlib::GzipReader.new(StringIO.new(body))
  puts gz.read
end

# http://ruby-doc.org/stdlib/libdoc/net/http/rdoc/classes/Net/HTTP.html
def fetch(uri_str, limit = 5)
  # You should choose better exception.
  raise ArgumentError, 'HTTP redirect too deep' if limit == 0

  uri = URI.parse(uri_str)
  ua = { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_2) AppleWebKit/535.7 (KHTML, like Gecko) Chrome/16.0.912.75 Safari/535.7", "Referer" => LIBRARY_REFERER_URL, "Host" => uri.host }
  #ua = { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_2) AppleWebKit/535.7 (KHTML, like Gecko) Chrome/16.0.912.75 Safari/535.7", "Referer" => LIBRARY_REFERER_URL, "Host" => uri.host, "Connection" => "keep-alive", "Accept-Encoding" => "gzip,deflate,sdch", "Accept-Language" => "en-US,en;q=0.8", "Accept-Charset" => "ISO-8859-1,utf-8;q=0.7,*;q=0.3", "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" }

  request = Net::HTTP::Get.new(uri.path, ua)
  #request.initialize_http_header({"User-Agent" => "Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)",
  #  "Referer" => LIBRARY_BASE_URL, "Host" => uri.host})
  response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
  case response
  when Net::HTTPSuccess     then puts response.body# inflate(response.body)# "#{response.body}\n#{response['Content-Encoding']}"
  when Net::HTTPRedirection then fetch(response['location'], limit - 1)
  else
    response.error!
  end
end

#books.each do |isbn|
books.each do |book|
=begin
  related_isbns = []
  page = Nokogiri::XML(open("http://www.librarything.com/api/thingISBN/" + isbn))
  #isbns = page.xpath('//isbn')
  page.xpath('//isbn').each do |related_isbn|
    related_isbns.push(related_isbn.text)
  end
  isbn_search_string = related_isbns.join('+or+')
  fetch("http://www.chipublib.org/search/results/?keywords=&isbn=" + "0060891548" + "&location=&advancedSearch=submitted")
=end
#  uri = URI.parse("http://www.chipublib.org/search/results/?keywords=&isbn=" + "0060891548" + "&location=&advancedSearch=submitted")
  #uri = URI.parse("http://www.chipublib.org/search/results/?keywords=&isbn=" + isbn_search_string + "&location=&format=Book&language=English&advancedSearch=submitted")
#  uri = URI.parse("http://www.chipublib.org/search/results/?keywords=&title=neuromancer&location=&format=Book&language=English&advancedSearch=submitted")

  #fetch("#{LIBRARY_SEARCH_URL}?keywords=&title=#{CGI.escape(book[:title])}&author=#{CGI.escape(book[:author])}&submitButton.x=52&submitButton.y=18&submitButton=Search&location=&advancedSearch=submitted")
  #fetch("#{LIBRARY_SEARCH_URL}?keywords=&title=blah&author=&submitButton.x=52&submitButton.y=18&submitButton=Search&location=&advancedSearch=submitted")
  fetch("http://www.chipublib.org/search/results/?keywords=&isbn=" + "0060891548" + "&location=&advancedSearch=submitted")
  #fetch("http://www.chipublib.org/search/results/?keywords=&title=test&author=&series=&subject=&isbn=&controlNumber=&callNumber=&publisher=&range=&published=&published2=&submitButton.x=68&submitButton.y=19&submitButton=Search&location=&format=&language=&audience=allAudiences&fict=allFormats&advancedSearch=submitted")
  #puts "#{LIBRARY_SEARCH_URL}?keywords=&title=#{CGI.escape(book[:title])}&author=#{CGI.escape(book[:author])}&location=&advancedSearch=submitted"
break
  page = Nokogiri::HTML(response.body)

  if response.code.to_s.index("Your search did not produce any results.") == -1
    puts page
    break
  elsif
    puts LIBRARY_SEARCH_URL + '?isbn=' + isbn_search_string + "&format=Book&advancedSearch=submitted"
  end

  sleep 1/10
end

