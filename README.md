###bars.json
a list of known bars.

###locations.json
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
