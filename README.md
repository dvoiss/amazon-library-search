### Heroku app to check which books from an Amazon wishlist are available at a given Chicago library

I wrote this after going to the library to return a book, at which point I needed to check my Amazon wishlist (which serves as my reading to-do list) to see what to get next. A smaller branch of the Chicago Library meant 90% of the items on my list weren't stocked at this location or were checked out. Items which are in transit, checked out, on hold, etc. or not in stock at the library are ignored.

This script grabs my Amazon wishlist, filters by books, and uses [Nokogiri](http://www.nokogiri.org) to parse the books into a collection (because Amazon does not expose wishlists via an api). The ISBN is parsed from Amazon and sent to [Library Thing](http://www.librarything.com)'s ISBN api to get related ISBN numbers for the same book; when a book has a new edition it is given a different ISBN number (some books on my wishlist have 20+ numbers).

The retrieved ISBNs are fed into the [Chicago Public Library](http://www.chipublib.org) search, this is done 5 ISBNs at a time as there is apparently a limit (though it isn't stated anywhere, too many ISBNs at once seems to result in 0 results even if they are in the library's system). If a "detail" result page is retrieved, we parse it to see if the book is checked out. If a search results page is retrieved, we parse it and make a request for each result to see the result's detail page so we can determine whether it is checked out or not.

### Usage

Run the sinatra app:

    bundle install
    ruby app.rb

Run with foreman:

    bundle install
    bundle exec foreman start

Heroku deploy:

    heroku create
    git push heroku master