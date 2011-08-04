#!/usr/bin/env ruby
#
# Simple example that takes all requests and forwards them to
# another API using EM-HTTP-Request. Information about the
# request and response is then stored into a Mongo database.
#

$: << "./config"
require 'boot'
require 'setup_load_paths'

$: << "../lib" << "./lib"

#require 'rubygems'
require 'goliath'
require 'em-mongo'
require 'em-synchrony/em-http'
require 'pp'

require 'yajl/json_gem'

require 'erb'
require 'yaml'

require "eventmachine"
require "fiber"
require 'active_record'

class Partner < ActiveRecord::Base
end

class MongoPg < Goliath::API
  include Goliath::Validation # errors

  use Goliath::Rack::Params

  class MissingApikeyError     < BadRequestError   ; end
  class RateLimitExceededError < ForbiddenError    ; end
  class InvalidApikeyError     < UnauthorizedError ; end
  
  attr_accessor :usage_info, :partner

  def on_headers(env, headers)
    env.logger.info 'proxying new request: ' + headers.inspect
    env['client-headers'] = headers
  end

  def response(env)
    start_time = Time.now.to_f

    params = {:head => env['client-headers'], :query => env.params}

    env.mongo.find( { :_id => 'test-bucket'}, :limit => 1 ).limit(1).each do |doc|
      self.usage_info = doc if doc
    end

    self.partner = Partner.find_by_key('a')

    unless self.partner
      raise InvalidApikeyError 
    end

    puts self.usage_info.inspect
    puts self.partner.inspect

    # XXX: check signature
    
    req = EM::HttpRequest.new("#{env.forwarder}#{env[Goliath::Request::REQUEST_PATH]}")
    resp = case(env[Goliath::Request::REQUEST_METHOD])
           when 'GET'  then req.get(params)
           when 'POST' then req.post(params.merge(:body => env[Goliath::Request::RACK_INPUT].read))
           when 'HEAD' then req.head(params)
           else p "UNKNOWN METHOD #{env[Goliath::Request::REQUEST_METHOD]}"
           end

    process_time = Time.now.to_f - start_time

    response_headers = {}
    resp.response_header.each_pair do |k, v|
      response_headers[to_http_header(k)] = v
    end

    #record(env, process_time, resp, env['client-headers'], response_headers)

    EM.next_tick do
      env.mongo.safe_update({ :_id => "test-bucket"}, { '$inc' => { :calls => 1 } }, :upsert => true)
    end

    [resp.response_header.status, response_headers, resp.response]
  end

  # Need to convert from the CONTENT_TYPE we'll get back from the server
  # to the normal Content-Type header
  def to_http_header(k)
    k.downcase.split('_').collect { |e| e.capitalize }.join('-')
  end

  # Write the request information into mongo
  def record(env, process_time, resp, client_headers, response_headers)
    e = env
    EM.next_tick do
      doc = {
        request: {
          http_method: e[Goliath::Request::REQUEST_METHOD],
          path: e[Goliath::Request::REQUEST_PATH],
          headers: client_headers,
          params: e.params
        },
        response: {
          status: resp.response_header.status,
          length: resp.response.length,
          headers: response_headers,
          body: resp.response
        },
        process_time: process_time,
        date: Time.now.to_i
      }

      if e[Goliath::Request::RACK_INPUT]
        doc[:request][:body] = e[Goliath::Request::RACK_INPUT].read
      end

      e.mongo.insert(doc)
    end
  end
end
