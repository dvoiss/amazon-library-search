## A mash-up of Amazon / Library Thing / Chicago Public Library

This is a Sinatra app which checks books from an Amazon wishlist (supplied by an email address) are available at a given Chicago library. All the relevant code is in `search.rb` with the Sinatra code in `app.rb`. The wishlist must be public so [Nokogiri](http://www.nokogiri.org) can parse it, this is necessary because Amazon does not expose wishlists via an API (more info below). Views are rendered using [haml](http://haml-lang.org).

### Demo

[http://cpl-search.herokuapp.com/](http://cpl-search.herokuapp.com/)

### Usage

Run the sinatra app:

    bundle install
    ruby app.rb

Or run with foreman:

    bundle install
    bundle exec foreman start

Deploy to Heroku with Cedar stack:

    heroku create --stack cedar
    git push heroku master

### About:

I wrote this after going to the library to return a book, at which point I needed to check my Amazon wishlist (which serves as my reading to-do list) to see what to get next. A smaller branch of the Chicago Library meant more than 90% of the items on my list weren't stocked at this location or were checked out. This app finds items which are available: items which are in transit, checked out, on hold, etc. or not in stock at the library are ignored.

The first step is to grab the Amazon wishlist, filtered by books, and use [Nokogiri](http://www.nokogiri.org) to parse the books into a collection (necessary because Amazon does not expose wishlists via an api). The ISBN is parsed from Amazon and sent to [Library Thing](http://www.librarything.com)'s ISBN api to get related ISBN numbers for the same book; when a book has a new edition it is given a different ISBN number (some books on my wishlist have 20+ numbers).

The retrieved ISBNs are fed into the [Chicago Public Library](http://www.chipublib.org) search, this is done 5 ISBNs at a time as there is apparently a limit (though it isn't stated anywhere, I've found that too many ISBNs at once result in 0 results even if they are in the library's system). If a "detail" result page is retrieved, we parse it to see if the book is checked out. If a search results page is retrieved, we parse it and make a request for each result to see the result's detail page so we can determine whether it is checked out or not.