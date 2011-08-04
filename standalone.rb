# Fill in your own spec for #establish_connection.

$: << "./config"
require 'boot'
require 'setup_load_paths'

require "eventmachine"
require "fiber"
require "active_record"
require "benchmark"

require 'logger'
require 'erb'

filename = File.join(File.dirname(__FILE__), 'config', 'database.yml')
ActiveRecord::Base.configurations = YAML::load(ERB.new(File.read(filename)).result)
ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations['development'])
#ActiveRecord::Base.logger = logger

ActiveRecord::Base.logger = Logger.new(STDOUT)
# ActiveRecord::Base.establish_connection :adapter      => "em_postgresql",
#                                         :port         => 5432,
#                                         :pool         => 2,
#                                         :username     => "cjbottaro",
#                                         :host         => "localhost",
#                                         :database     => "template1",
#                                         :wait_timeout => 2

def spawn(n)
  n.times.collect do
    Fiber.new do
      begin
        ActiveRecord::Base.connection.execute "select pg_sleep(1.1)"
        ActiveRecord::Base.clear_active_connections!
      rescue => e
        puts e.inspect
      end
    end.tap{ |fiber| fiber.resume }
  end
end

def join(fibers)
  fibers.each do |fiber|
    while fiber.alive?
      current_fiber = Fiber.current
      EM.next_tick{ current_fiber.resume }
      Fiber.yield
    end
  end
end

EM.run do
  Fiber.new do
    time = Benchmark.realtime do
      fibers = spawn(5)
      join(fibers)

      puts "first batch done"

      fibers = spawn(5)
      join(fibers)
    end
    puts time
    EM.stop
  end.resume
end

