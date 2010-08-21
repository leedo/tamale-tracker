#!/usr/bin/ruby

require 'rubygems'
require 'yelp'
require 'json'

yelpkey_fn = '.yelpkey'
locations_fn = '../data/locations_with_neighborhoods.json'

# Get Locations ready 
puts "Reading in locations JSON file"
begin
  locations_f = File.open locations_fn, 'r'
rescue
  raise "Can't find #{locations_fn}... what the heck?"
end

locations_data = ''
locations_f.each_line { |l| locations_data += l }
locations_f.close

puts "Parsing JSON string into Ruby object"
begin
  locations_data = JSON.parse locations_data
rescue
  raise "Can't parse locations data for some reason."
end
  

# Put your API key in a file in this directory called .yelpkey
begin
  key = File.open(yelpkey_fn, 'r').gets
rescue
  raise "Can't find #{yelpkey_fn}, make it."
end

y = Yelp.new(key)

puts "Steppin'"
place_cache = {}
locations_data[0...10].each do |l|
  # We can't do anything without a street location
  if l['bar']['street']
    street = l['bar']['street'] + ", Chicago, IL"
    name = l['bar']['name']
    # Have we already asked yelp about this place?
    neighborhood = l['bar']['neighborhood'] ? l['bar']['neighborhood'] : nil
    if neighborhood
      puts "Neighborhood for #{name} already in stored in JSON (#{neighborhood})."
      next
    end
    # Is it in our session yelp cache?
    if place_cache[name]
      cached_neighborhood = place_cache[name]['bar']['neighborhood']
      puts "We've already asked yelp for #{name}'s neighborhood (#{cached_neighborhood}) this session."
      # No need to hit yelp for dupes.
      if cached_neighborhood
        l['bar']['neighborhood'] = cached_neighborhood
        next
      end
    end
    # Ok, so there's no neighborhood for this place in the JSON
    #  nor have we got a neighborhood for it from Yelp during
    #  this session, lets ask yelp about it.
    neighborhood = y.neighborhood_search street
    # Update huge locations structure
    l['bar']['neighborhood'] = neighborhood
    puts "Asked yelp for neighborhood for #{name} and got #{neighborhood}, storing."
    # Cache this location name for this session to cut down
    #   on yelp requests
    place_cache[name] = l
  end
end

# Once we're done, we can write out the locations JSON and it will let us
# progressively bring in location names for places we haven't asked
# yelp about yet.
locations_f = File.open locations_fn, 'w' do |f|
  puts "Dumping modified locations structure"
  locations_json = JSON.pretty_generate locations_data
  f.write locations_json
end
