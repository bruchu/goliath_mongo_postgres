#require 'postgres-pr/postgres-compat'
#require 'active_record/connection_adapters/em_pg_adapter'

import 'http_log' # pull in config/http_log.rb

require 'erb'
require 'yaml'

RAILS_ENV = Goliath.env

config['mongo_auth_db'] = EventMachine::Synchrony::ConnectionPool.new(:size => 20) do
  conn = EM::Mongo::Connection.new('localhost', 27017, 1, {:reconnect_in => 1})
  conn.db("zambosa_#{ Goliath.env}")
end

#require 'rack/fiber_pool'
require 'active_record'
require 'active_record/connection_adapters/abstract_adapter'
require 'active_record/connection_adapters/em_postgresql_adapter'

filename = File.join(File.dirname(__FILE__), 'config', 'database.yml')
puts filename
#ActiveRecord::Base.configurations = YAML::load(File.open(filename))
ActiveRecord::Base.configurations = YAML::load(ERB.new(File.read(filename)).result)
puts ActiveRecord::Base.configurations[Goliath.env.to_s]

ActiveRecord::Base.default_timezone = :utc
ActiveRecord::Base.logger = logger
#ActiveRecord::Base.time_zone_aware_attributes = true
# ActiveRecord::ConnectionAdapters::ConnectionPool.new(Struct.new(:config).new({})) do
#   conn = ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[Goliath.env.to_s])
# end

ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[Goliath.env.to_s])
#   :adapter  => 'em_postgresql',
# #  :adapter  => 'neverblock_postresql',
#   :database => 'zambosa_dev',
#   :username => 'chub',
#   :password => 'chub',
#   :host     => 'localhost')

#  ActiveRecord::Base.configurations[Goliath.env.to_s])
#puts 'connected?=', ActiveRecord::Base.connected?
