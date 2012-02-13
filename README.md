# A script to run before I go to the library...

I wrote this after going to the library to return a book, at which point I needed to check my Amazon wishlist (which serves as my reading to-do list) to see what to get next. A smaller branch of the Chicago Library meant 90% of the items on my list weren't stocked at this location or were checked out.

This script grabs my Amazon wishlist, filters by books, and uses [Nokogiri](http://www.nokogiri.org) to parse the books into a collection (Amazon does not expose wishlists via an api). The ISBN is parsed from Amazon and sent to [Library Thing](http://www.librarything.com)'s ISBN api to get related ISBN numbers for the same book; when a book has a new edition it is given a different ISBN number (some books on my wishlist have 20+ numbers).

The retrieved ISBNs are fed into the [Chicago Public Library](http://www.chipublib.org) search, this is done 5 ISBNs at a time as there is apparently a limit (though it isn't stated anywhere, too many ISBNs at once seems to result in 0 results even if they are in the library's system). If a "detail" result page is retrieved, we parse it to see if the book is checked out. If a search results page is retrieved, we parse it and make a request for each result to see the result's detail page so we can determine whether it is checked out or not. See the example below for output.

# Usage

Add your email and leave the library-id blank to search entire system. Todo: make these ids available so they don't need to be looked up at [chipublib.org](http://www.chipublib.org).

    $ ruby search.rb
    Usage: search.rb [email] [library-id]

    Library id can be left blank, otherwise an id is needed corresponding to
    the library you want, example: 70 for Chinatown, 320 for Bucktown-Wicker park

# Example

Local library search (Bucktown Wickerpark branch):

    $ ruby search.rb me@email.com 320
    Retrieving wishlist
    Finding books...

    The Prince (Bantam Classics) is available at your library.
    Boneshaker (Sci Fi Essential Books) is available at your library.
    Where Good Ideas Come From: The Natural History of Innovation is available at your library.
    River of Gods is available at your library.
    The Name of the Rose: including the Author's Postscript is available at your library.
    Foucault's Pendulum is available at your library.

No library branch specified:

    $ ruby search.rb me@email.com
    Retrieving wishlist
    Finding books...

    The Pattern On The Stone: The Simple Ideas That Make Computers Work (Science Masters Series) is available at: HWLC 4th Floor, Sulzer Regional, Oriole Park
    On Writing Well, 30th Anniversary Edition: The Classic Guide to Writing Nonfiction is available at: Chinatown, Sulzer Regional
    The Lifecycle of Software Objects is available at: HWLC 1st Floor
    Last Call is available at: Sulzer Regional, HWLC 7th Floor
    Delivering Happiness: A Path to Profits, Passion, and Purpose is available at: Brighton Park, Chicago Lawn, HWLC 1st Floor, HWLC 4th Floor, Humboldt Park, Jefferson Park, Jeffery Manor, Mayfair, North Pulaski, Roosevelt, South Shore, Walker, Water Works, West Lawn, West Town, Woodson Regional, Wrightwood-Ashburn
    Innumeracy: Mathematical Illiteracy and Its Consequences (Vintage) is available at: HWLC 4th Floor, Rogers Park, Uptown, Legler
