#!/usr/bin/ruby

require 'rubygems'
require 'yelp'
require 'json'

yelpkey_fn = '.yelpkey'
bar_fn = '../data/bars.json'

# Get Bar Data
puts "Reading in bars JSON file"
begin
  bar_f = File.open bar_fn, 'r'
rescue
  raise "Can't find #{bar_fn}... what the heck?"
end

bar_data = ''
bar_f.each_line { |l| bar_data += l }
bar_f.close

puts "Parsing JSON string into Ruby object"
begin
  bar_data = JSON.parse bar_data
rescue
  raise "Can't parse bar data for some reason."
end
  

# Put your API key in a file in this directory called .yelpkey
begin
  key = File.open(yelpkey_fn, 'r').gets
rescue
  raise "Can't find #{yelpkey_fn}, make it."
end

y = Yelp.new(key)

puts "Steppin'"

bar_data.each do |b|
  # We can't do anything without a street location
  if b['street']
    address = b['street'] + ", Chicago, IL"
    name = b['name']
    # Have we already asked yelp about this place?
    next if b['neighborhood']
    # Ok, so there's no neighborhood for this place in the JSON
    #  nor have we got a neighborhood for it from Yelp during
    #  this session, lets ask yelp about it.
    begin
      neighborhood = y.neighborhood_search address
    rescue
      puts "Something insane happened...lets get out of here"
      break
    end
    # Update bar structure
    b['neighborhood'] = neighborhood
    puts "Asked yelp for neighborhood for #{name} and got #{neighborhood}, storing."
  end
end

# Once we're done, we can write out the bar JSON and it will let us
# progressively bring in neighborhoods for places we haven't asked
# yelp about yet.
bar_f = File.open bar_fn, 'w' do |f|
  puts "Dumping modified bar structure"
  bar_json = JSON.pretty_generate bar_data
  f.write bar_json
end
