#!/usr/bin/ruby

require 'rubygems'
require 'yelp'
require 'json'

yelpkey_fn = '.yelpkey'
locations_fn = '../data/locations.json'

# Get Locations ready 
begin
  locations_f = File.open(locations_fn, 'r')
rescue
  raise "Can't find #{locations_fn}... what the heck?"
end

locations_data = ''
locations_f.each_line { |l| locations_data += l }

begin
  locations_data = JSON.parse(locations_data)
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

place_cache = {}

locations_data[0...5].each do |l|
  # We can't do anything without a street location
  if l['bar']['street']
    street = l['bar']['street'] + ", Chicago, IL"
    name = l['bar']['name']
    # Have we already asked yelp about this place?
    neighborhood = l['bar']['neighborhood'] ? l['bar']['neighborhood'] : nil
    continue if neighborhood
    # Is it in our session yelp cache?
    if place_cache[name]
      continue if place_cache[name]['bar']['neighborhood']
    end
    # Ok, so there's no neighborhood for this place in the JSON
    #  nor have we got a neighborhood for it from Yelp during
    #  this session, lets ask yelp about it.
    neighborhood = y.neighborhood_search(street)
    l['bar']['neighborhood'] = neighborhood
    place_cache[name] = l
  end
end

puts place_cache.inspect
