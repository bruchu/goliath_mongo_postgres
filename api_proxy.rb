#!/usr/bin/env ruby

$: << "./config"

require 'pp'
require 'boot'
require 'setup_load_paths'

require 'goliath'
require 'em-mongo'
require 'em-http'
require 'em-synchrony/em-http'
require 'yajl/json_gem'
require 'active_record'

require 'goliath/synchrony/response_receiver'
require File.join(File.dirname(__FILE__), 'http_log') # Use the HttpLog as our actual endpoint, but include this in the middleware

#require 'pg_patches'
require 'zambosa_signature'

# Usage:
#
# First launch a dummy responder, like hello_world.rb or test_rig.rb:
# ruby ./examples/hello_world.rb -sv -p 8080 -e prod &
#
# Then launch this script
# ruby ./examples/auth_and_rate_limit.rb -sv -p 9000 --config $PWD/examples/config/auth_and_rate_limit.rb
#

# Tracks and enforces account and rate limit policies.
#
# Before the request:
#
# * validates the apikey exists
# * launches requests for the account and current usage (hourly rate limit, etc)
#
# It then passes the request down the middleware chain; execution resumes only
# when both the remote request and the auth info have returned.
#
# After remote request and auth info return:
#
# * Check the account exists and is valid
# * Check the rate limit is OK
#
# If it passes all those checks, the request goes through; otherwise we raise an
# error that Goliath::Rack::Validator turns into a 4xx response
#
# WARNING: Since this passes ALL requests through to the responder, it's only
# suitable for idempotent requests (GET, typically).  You may need to handle
# POST/PUT/DELETE requests differently.
#
#
class AuthReceiver # < Goliath::Synchrony::MultiReceiver
  include Goliath::Validation
  include Goliath::Rack::Validator
  attr_accessor :partner, :usage_info

  # time period to aggregate stats over, in seconds
  TIMEBIN_SIZE = 60 * 60

  class MissingApikeyError     < BadRequestError   ; end
  class RateLimitExceededError < ForbiddenError    ; end
  class InvalidApikeyError     < UnauthorizedError ; end

  def initialize(env, db_name)
    @env = env
    @db = env.config[db_name]
  end

  def db
    @db
  end
  
  def pre_process
    self.partner = Partner.find_by_key(env.params['app'])
    db.collection("UsageInfo").find({ :_id => self.usage_id }, :limit => 1) do |result|
      self.usage_info = result
    end

    # charge_usage
    db.collection('UsageInfo').update({ :_id => self.usage_id },
      { '$inc' => { :calls   => 1 } }, :upsert => true)

    puts self.partner.inspect
    puts self.usage_info.inspect

    first('UsageInfo',   { :_id => usage_id }){|res| self.usage_info   = res }
    env.trace('pre_process_end')
  end

  def post_process
    env.trace('post_process_beg')
    env.logger.info [partner, usage_info].inspect
    self.partner ||= {}
    self.usage_info   ||= {}

    inject_headers

    EM.next_tick do
      safely(env){ charge_usage }
    end

    safely(env, headers) do
      check_signature!
      check_rate_limit!

      env.trace('post_process_end')
      [status, headers, body]
    end
  end

  # ===========================================================================

  def validate_app_key!
    if env.params['app'].to_s.empty?
      raise MissingApikeyError
    end

    self.partner = EM.synchrony do
      ActiveRecord::Base.establish_connection(
          :adapter  => 'em_postgresql',
          :database => 'zambosa_dev',
          :username => 'chub',
          :password => 'chub',
          :host     => 'localhost')
      #Partner.find_by_key(env.params['app'])
      Fiber.yield Partner.find_by_key(env.params['app'])
      #Fiber.yield(p)
    end

    puts self.partner.inspect
    #puts f.resume.inspect

    #puts Being.find(env.params['id']).inspect
    #puts Partner.find_by_key(env.params['app']).inspect
    #end
    #puts 'partner=', self.partner
#       Fiber.new {
#         ActiveRecord::Base.establish_connection(
#   :adapter  => 'em_postgresql',
# #  :adapter  => 'neverblock_postresql',
#   :database => 'zambosa_dev',
#   :username => 'chub',
#   :password => 'chub',
#   :host     => 'localhost')
#         puts Being.find(env.params['id']).inspect
#         yield Partner.find_by_key(env.params['app'])
#       }.resume
#     }
    puts 'partner=%s' % self.partner.inspect
    unless self.partner
      raise MissingApikeyError
    end
  end

  def check_signature!
    puts self.partner.inspect
    unless self.partner.valid == true
      raise InvalidApikeyError
    end
  end

  def check_rate_limit!
    return true if usage_info['calls'].to_f <= partner['max_call_rate'].to_f
    raise RateLimitExceededError
  end

  def charge_usage
    update('UsageInfo', { :_id => usage_id },
      { '$inc' => { :calls   => 1 } }, :upsert => true)
  end

  def inject_headers
    headers.merge!({
        'X-RateLimit-MaxRequests' => partner['max_call_rate'].to_s,
        'X-RateLimit-Requests'    => usage_info['calls'].to_s,
        'X-RateLimit-Reset'       => timebin_end.to_s,
      })
  end

  # ===========================================================================

  def usage_id
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

class Partner < ActiveRecord::Base
end

class Being < ActiveRecord::Base
end

class ApiProxy < HttpLog
  include Goliath::Validation
  
  use Goliath::Rack::Tracer, 'X-Tracer'
  use Goliath::Rack::Params             # parse & merge query and body parameters
  #use Goliath::Rack::AsyncAroundware, AuthReceiver, 'mongo_auth_db'

  use Goliath::Rack::Validation::RequestMethod, %w(GET)           # allow GET requests only
  use Goliath::Rack::Validation::RequiredParam, { :key => 'app' }
  attr_accessor :usage_info, :partner

  # time period to aggregate stats over, in seconds
  TIMEBIN_SIZE = 60 * 60

  class MissingApikeyError     < BadRequestError   ; end
  class RateLimitExceededError < ForbiddenError    ; end
  class InvalidApikeyError     < UnauthorizedError ; end
  class InvalidSignatureError     < UnauthorizedError ; end

  def check_signature!(env)
    puts 'url=%s' % "http://#{ env.HTTP_HOST.downcase }#{ env.REQUEST_URI }"
    unless ZambosaSignature.verify_url(self.partner.key, self.partner.secret, "http://#{ env.HTTP_HOST.downcase }#{ env.REQUEST_URI }")
      puts 'invalid signature'
      raise InvalidSignatureError
    end
  end
  
  def response(env)
    self.partner = Partner.find_by_key(env.params['app'])

    unless self.partner
      raise InvalidApikeyError
    end

    #puts env.pretty_inspect
    check_signature!(env)
    
    env.mongo_auth_db.collection("UsageInfo").find({ :_id => self.usage_id }, :limit => 1) do |result|
      self.usage_info = result
    end

    # charge_usage
    env.mongo_auth_db.collection('UsageInfo').update({ :_id => self.usage_id },
      { '$inc' => { :calls   => 1 } }, :upsert => true)

    puts self.partner.inspect
    puts self.usage_info.inspect

    

    r = super(env)
  end
  # ===========================================================================
  def usage_id
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





