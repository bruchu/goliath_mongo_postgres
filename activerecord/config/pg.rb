#require 'postgres-pr/message'
#require 'em_postgresql'
#require 'pg'

require 'postgres-pr/postgres-compat'

# filename = File.join(Rails.root, 'config', 'database.yml')
# ActiveRecord::Base.configurations = YAML::load(ERB.new(File.read(filename)).result)
ActiveRecord::Base.default_timezone = :utc
#ActiveRecord::Base.logger = Rails.logger
#    ActiveRecord::Base.time_zone_aware_attributes = true
#ActiveRecord::Base.establish_connection

# use Rack::FiberPool do |fp|
#   ActiveRecord::ConnectionAdapters.register_fiber_pool(fp)
# end
# # ConnectionManagement must come AFTER FiberPool
# use ActiveRecord::ConnectionAdapters::ConnectionManagement

ActiveRecord::Base.logger = logger
ActiveRecord::Base.establish_connection(:adapter  => 'em_postgresql',
                                        :database => 'goliath_test',
                                        :username => 'chub',
  :password => 'chub',
                                        :host     => 'localhost')
