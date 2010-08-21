require 'rubygems'
require 'net/http'
require 'CGI'
require 'json'

class Yelp
  class << self; attr_accessor :api_domain end
  attr_accessor :api_key
  @api_domain = 'api.yelp.com'

  def neighborhood_search(location)
    endpoint = '/neighborhood_search'
    parameters = {
      "location" => location
    }
    response = self.request endpoint, parameters
    response['neighborhoods'][0]['name']
  end
  
  def request(path, parameters)
    raise "Please specify an API key" unless @api_key
    parameters["ywsid"] = @api_key
    paramlist = []
    for parameter in parameters.keys
      paramlist.push(["#{parameter}=#{CGI::escape(parameters[parameter])}"])
    end
    path += "?#{paramlist.join '&'}"
    begin
      raw_result = Net::HTTP.get Yelp::api_domain, path
    rescue
      raise "Failed to access Yelp"
    end
    
    begin
      parsed_result = JSON.parse raw_result
    rescue
      raise "Failed to parse Yelp response"
    end
    
    return parsed_result if parsed_result['message']['text'] == 'OK'
    raise result['message']['text']
  end
  
  def initialize(api_key, output_type='json')
    @api_key = api_key
    @output_type = output_type 
  end
end