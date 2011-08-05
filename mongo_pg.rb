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

# class AuthAndRateLimitReceiver < Goliath::Synchrony::MultiReceiver

#   def initialize(env)
#     @env = env
#     @pending_queries = 0
#     @db = env.config[db_name]
#   end
  
#   def pre_process

#     validate_app_key!

#     @env.mongo.find( { :_id => self.usage_id }, :limit => 1 ).limit(1).each do |doc|
#       self.usage_info = doc if doc
#     end

#     check_rate_limit!
#     check_signature!
#   end

#   def post_process

#   end
# end

class MongoPg < Goliath::API
  include Goliath::Validation # errors

  use Goliath::Rack::Params

  #use Goliath::Rack::AsyncAroundware, AuthAndRateLimitReceiver, env

  TIMEBIN_SIZE = 60 * 60
  DEFAULT_RATE_LIMIT = 10

  class MissingApikeyError     < BadRequestError   ; end
  class RateLimitExceededError < ForbiddenError    ; end
  class InvalidApikeyError     < UnauthorizedError ; end
  
  attr_accessor :usage_info, :partner

  def on_headers(env, headers)
    env.logger.info 'proxying new request: ' + headers.inspect
    env['client-headers'] = headers
  end

  def response(env)
    self.partner = nil
    self.usage_info = nil
    
    start_time = Time.now.to_f
    params = {:head => env['client-headers'], :query => env.params}
    validate_app_key!

    #self.usage_info = env.mongo.find_one( { :_id => self.usage_id } )
    rr = env.mongo.first( { :_id => self.usage_id } )
    rr.callback do |docs|
      puts 'docs.inspect=%s' % docs if docs
    end

    rr.errback do |err|
      raise *err
    end
    
    check_rate_limit!
    check_signature!

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

    charge_usage

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


  def validate_app_key!
    if env.params['app'].to_s.empty?
      raise MissingApikeyError
    end

    self.partner = Partner.find_by_key(env.params['app'])
    puts self.partner.inspect
    raise MissingApikeyError unless self.partner
  end

  def check_signature!
    unless self.partner.secret
      raise InvalidApikeyError
    end
  end

  def check_rate_limit!
    puts 'usage_info=%s' % self.usage_info.inspect

    # check for UsageInfo document not found case
    return unless usage_info
    
    if usage_info['calls'].to_f > ( partner['max_call_rate'] || DEFAULT_RATE_LIMIT ).to_f
      charge_overlimit
      raise RateLimitExceededError
    end
  end

  def charge_usage
    e = env
    EM.next_tick do
      e.mongo.safe_update({ :_id => usage_id }, { '$inc' => { :calls => 1 } }, :upsert => true)
      e.mongo.find( { :_id => self.usage_id }, :limit => 1 ).limit(1).each do |doc|
        puts doc.inspect if doc
      end
    end
  end

  def charge_overlimit
    e = env
    EM.next_tick do
      e.mongo.safe_update({ :_id => usage_id }, { '$inc' => { :overlimit => 1 } }, :upsert => true)
    end
  end

  # ===========================================================================

  def usage_id
    puts "#{ self.partner.id }-#{timebin}"
    "#{ self.partner.id }-#{timebin}"
  end

  def timebin
    @timebin ||= timebin_beg
  end

  def timebin_beg
    ((Time.now.to_i / TIMEBIN_SIZE).floor * TIMEBIN_SIZE)
  end

  def timebin_end
    timebin_beg + TIMEBIN_SIZE
  end
end

