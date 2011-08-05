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

require 'zambosa_signature'

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
  DEFAULT_RATE_LIMIT = 25

  ERRORS = [
    ["missing api key", BadRequestError],
    ["rate limit exceeded", ForbiddenError],
    ["invalid api key", UnauthorizedError],
    ["invalid signature", UnauthorizedError]
  ]

  ERRORS.each do |msg, base_klass|
    klass_name = "#{msg.gsub(/\W+/, '_')}Error".camelize.gsub(/ErrorError$/, "Error")
    klass = Class.new(base_klass)
    klass.class_eval(%Q{
      def initialize
        super('#{ msg }')
      end }, __FILE__, __LINE__)
    self.const_set(klass_name, klass)
  end
    
  # class MissingApikeyError < BadRequestError
  #   def initialize
  #     super("missing api key")
  #   end
  # end

  attr_accessor :usage_info, :partner

  def on_headers(env, headers)
    env.logger.info 'proxying new request: ' + headers.inspect
    env['client-headers'] = headers
  end

  def response(env)
    @timebin = nil
    self.partner = nil
    self.usage_info = nil
    
    start_time = Time.now.to_f
    params = {:head => env['client-headers'], :query => env.params}
    validate_app_key!

    # make this call "synchronous"
    f = Fiber.current
    env.mongo.first( { :_id => self.usage_id } ).callback do |doc|
      self.usage_info = doc
      f.resume
    end
    Fiber.yield
    
    check_rate_limit!
    check_signature!(env)

    # code to help testing concurrency
    # f = Fiber.current  
    # EventMachine.add_timer 3, proc { f.resume }  
    # Fiber.yield

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

    record(env, process_time, resp, env['client-headers'], response_headers)

    if resp.response_header.status == 200
      charge_usage
    else
      charge_forwarder_failure
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

      puts doc.inspect
      #e.mongo.insert(doc)
    end
  end


  def validate_app_key!
    if env.params['app'].to_s.empty?
      raise MissingApiKeyError
    end

    self.partner = Partner.find_by_key(env.params['app'])
    puts self.partner.inspect
    raise MissingApiKeyError unless self.partner
  end

  def check_signature!(env)
    unless self.partner.secret
      raise InvalidApikeyError
    end

    puts 'url=%s' % "http://#{ env.HTTP_HOST.downcase }#{ env.REQUEST_URI }"
    unless ZambosaSignature.verify_url(self.partner.key, self.partner.secret, "http://#{ env.HTTP_HOST.downcase }#{ env.REQUEST_URI }")
      charge_invalid_signature
      raise InvalidSignatureError
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
    charge(:calls => 1)
  end

  def charge_invalid_signature
    charge(:invalid_signature => 1)
  end

  def charge_overlimit
    charge(:overlimit => 1)
  end

  def charge_forwarder_failure
    charge(:forwarder_failure => 1)
  end

  def charge(inc_options)
    e = env
    EM.next_tick do
      e.mongo.safe_update({ :_id => usage_id }, { '$inc' => inc_options }, :upsert => true)
      e.mongo.find( { :_id => self.usage_id }, :limit => 1 ).limit(1).each do |doc|
        puts doc.inspect if doc
      end
    end
  end
  

  # ===========================================================================

  def usage_id
    #puts "#{ self.partner.id }-#{timebin}"
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

