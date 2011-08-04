#!/usr/bin/env ruby

$: << "./config"
require 'boot'
require 'setup_load_paths'

require 'em-mongo'
require 'em-synchrony'
require 'em-synchrony/em-http'
require 'yajl/json_gem'

require 'erb'
require 'yaml'
require 'log4r'

require "eventmachine"
require "fiber"
require 'active_record'
#require 'active_record/connection_adapters/em_postgresql_adapter'

class Partner < ActiveRecord::Base
end

class EchoServer < EM::Connection
  @@env = 'development'

  attr_accessor :config, :sql, :mongo, :usage_info, :partner

  def initialize
    @config = {}
    @mongo = EventMachine::Synchrony::ConnectionPool.new(:size => 2) do
      conn = EM::Mongo::Connection.new('localhost', 27017, 1, {:reconnect_in => 1})
      conn.db("zambosa_#{ @@env }")
    end

    filename = File.join(File.dirname(__FILE__), 'config', 'database.yml')
    ActiveRecord::Base.configurations = YAML::load(ERB.new(File.read(filename)).result)
    ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[@@env])
    ActiveRecord::Base.logger = logger
  end

  def logger
    unless @logger
      @logger = Log4r::Logger.new('db_synchrony')
      @logger.level = Log4r::DEBUG
    end
    @logger
  end
  
  def post_init
    puts "-- someone connected to the echo server!"
  end

  def receive_data data
    # lookup("UsageInfo", { :_id => 'test-bucket' }, :limit => 1) do |result|
    #   puts result
    #   self.usage_info = result
    # end

    # Fiber.new {
    #   @mongo.collection("UsageInfo").find({ :_id => 'test-bucket'}, :limit => 1) do |result|
    #     self.usage_info = result
    #   end
    # }.resume

    # EventMachine.synchrony do
    #   @mongo.collection("UsageInfo").find({ :_id => 'test-bucket'}, :limit => 1) do |result|
    #     self.usage_info = result
    #   end
    #   EventMachine.stop
    # end
    #f = Fiber.current

    # deferrable = ::EM::DefaultDeferrable.new
    
    # f = Fiber.new {
      
    #   @mongo.collection("UsageInfo").find({ :_id => 'test-bucket'}, :limit => 1) do |result|
    #     puts result.inspect
    #     result.first
    #   end
    # }
    # puts self.usage_info.inspect

    EventMachine.synchrony do
      send_data ">>> you sent: #{ data }"

      #db = EM::Mongo::Connection.new('localhost', 27017, 1, {:reconnect_in => 1}).db("zambosa_development")
      #puts @mongo.inspect
      collection = @mongo.collection("UsageInfo")
      collection.find( { :_id => 'test-bucket'}, :limit => 1 ).limit(1).each do |doc|
        self.usage_info = doc if doc
      end
      # EM.next_tick do
      #   collection = @mongo.collection("UsageInfo")
      #   puts collection.inspect
      #   puts collection.size.data
      #   puts 'size=%s' % collection.size.data
      #   #cursor = collection.find({ :_id => 'test-bucket'}, :limit => 1)
      #   cursor = collection.find
      #   resp = cursor.to_a
      #   puts 'resp=', resp
      #   resp.callback do |documents|
      #     puts "I just got #{documents.length} documents! I'm really cool!"
      #   end
      #   self.usage_info = resp.callback.first.inspect
        
      #   # collection.find({ :_id => 'test-bucket'}, :limit => 1).to_a.each do |result|
      #   #   self.usage_info = result.first
      #   #   puts result.first
      #   # end

      self.partner = Partner.find_by_key('a')

      puts self.usage_info.inspect
      puts self.partner.inspect

      # #EM.next_tick do
      #puts @mongo.collection("UsageInfo").update({ :_id => "test-bucket"}, { '$inc' => { :calls => 1 } }, :upsert => true)
      collection.safe_update({ :_id => "test-bucket"}, { '$inc' => { :calls => 1 } }, :upsert => true)
      #end
    end

    # Fiber.new do
    #   Partner.find_by_key('a')
    #   EM.stop
    # end.resume

    # puts '1:', f.resume
    # puts '2:', f.resume
    # puts '3:', f.resume
    
  end

  def lookup(collection, selector, opts, &block)
    @mongo.collection(collection).find(selector, opts) do |result|
      yield result
    end
  end

end

EventMachine.run do
  # hit Control + C to stop
  Signal.trap("INT")  { EventMachine.stop }
  Signal.trap("TERM") { EventMachine.stop }

  EventMachine.start_server("0.0.0.0", 10000, EchoServer)
end

# EM.run {

#   sql.query("SELECT * from partners where partners.id='a' limit 1") do |status, result, errors|
#     puts status
#     puts result
#     puts errors
#     if status
#       puts results.rows.inspect
#       account_info = result.rows.first
#     end
#   end
# }
