##Files

###data/bars.json
a list of known bars.

###data/locations.json
a list of tweets matched up to the known bars.

###tools/dump_tweets
will pull down any new tweets from @tamaletracker and insert it in
a sqlite database, tweets.db. If tweets.db does not exist it will
create it. You need to pass a --username and --password option.

###tools/extract_names
will go through the tweets in tweets.db and attempt to associate
them with a bar name from bars.json. It uses some janky heuristics
to pull out what looks like a bar name, and then matches that to
a bar from bars.json using the levenshtein distance.

###tools/add_neighborhoods.rb
Will go through the known bars file. For bars that have street
components and no known neighborhood, we will ask yelp if they
know which neighborhood its in. 

###tools/yelp.rb
A Yelp class that, so far, only supports querying for neighborhoods
from street addresses

###tools/.yelpkey
A file containing a yelp API key that you'll need to add yourself.
Get a key here: http://www.yelp.com/developers/getting_started/api_access
Unfortunately limited to 100 queries per day unless you can show them
you have a working application ;(

##Requirements

###perl
* DBI, DBD::SQLite
* Any::Moose
* Net::Twitter::Lite
* Path::Class
* Date::Parse
* JSON

Assuming perl is installed, they can all be installed with:
    tools/cpanm --sudo DBD::SQLite Any::Moose Net::Twitter::Lite Path::Class Date::Parse JSON

###ruby
* json

Install with rubygems
    sudo gem install json
