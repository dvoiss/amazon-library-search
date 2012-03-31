# The server code for the Amazon / Library search app:
# cpl-search.herokuapp.com
# github.com/dvoiss/amazon-library-search/

require 'sinatra'
require 'sinatra/streaming'
require 'haml'
require 'thin'

# library-search / amazon / ISBN-thing code in 'search.rb'
require './search'

set :server, :thin

get '/' do
  @title = "Amazon CPL Library Search"
  haml :index
end

get '/retrieve/:email/:code/:location' do
  library_code      = params[:code] == "0" ? "" : params[:code]
  library_location  = params[:location]
  content_type "text/event-stream"
  stream do |out|
    begin
      books = get_wishlist(params[:email], out)
      find_books(books, library_code, library_location, out) unless books.nil? || books.empty?
      out << "data: #{nil}\n\n"
    rescue IOError
      puts "Stream not opened for writing..."
      out.flush
    end
  end
end

error do
  @title = "Sorry, error occurred."
  haml :error
end

not_found do
  @title = "404"
  haml :error
end