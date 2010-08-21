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
  
puts locations_data[0].inspect

# Put your API key in a file in this directory called .yelpkey
begin
  key = File.open(yelpkey_fn, 'r').gets
rescue
  raise "Can't find #{yelpkey_fn}, make it."
end

y = Yelp.new(key)



