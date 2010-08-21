#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'net/http'
require 'CGI'

def get_latlong(street)
  domain = "maps.google.com"
  path = "/maps/api/geocode/json"
  parameters = {
    "address" => street + " Chicago, IL",
    "sensor" => "false",
  }
  path += "?" + parameters.map do |parameter, value|
    [parameter, CGI.escape(value)].join("=")
  end.join("&")
  result = JSON.parse(Net::HTTP.get domain, path)
  result['results'][0]['geometry']['location']
end

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
  
puts "Steppin'"

bar_data.each do |b|
  # We can't do anything without a street location
  if b['street']
    address = b['street'] + ", Chicago, IL"
    name = b['name']
    # Have we already asked yelp about this place?
    next if b['location']
    # Ok, so there's no neighborhood for this place in the JSON
    #  nor have we got a neighborhood for it from Yelp during
    #  this session, lets ask yelp about it.
    begin
      geodata = get_latlong address
    rescue
      puts "Something insane happened...lets get out of here"
      break
    end
    # Update bar structure
    b['location'] = geodata
    puts "Asked Google for geolocation for #{name} and got #{geodata.inspect}, storing."
  end
end

bar_f = File.open bar_fn, 'w' do |f|
  puts "Dumping modified bar structure"
  bar_json = JSON.pretty_generate bar_data
  f.write bar_json
end
