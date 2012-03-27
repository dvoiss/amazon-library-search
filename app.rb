require 'sinatra'
require 'sinatra/streaming'

# library-search / amazon / ISBN-thing code in 'search.rb'
require './search'

set :server, :thin

get '/' do
  erb :index
end

get '/retrieve/:email/:library' do
  library = params[:library] == "0" ? "" : params[:library]
  content_type "text/event-stream"
  stream do |out|
    begin
      books = get_wishlist(params[:email], out)
      find_books(books, library, out) unless books.nil? || books.empty?
      out << "data: #{nil}\n\n"
    rescue IOError
      puts "Stream not opened for writing..."
      out.flush
    end
  end
end

error do
  title 'Sorry, error occurred.'
  erb :error
end

not_found do
  title '404'
  erb :error
end