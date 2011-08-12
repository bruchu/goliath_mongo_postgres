config['forwarder'] = 'http://localhost:3000/api'

environment(:development) do
  config['mongo'] = EventMachine::Synchrony::ConnectionPool.new(size: 20) do
    # Need to deal with this just never connecting ... ?
    conn = EM::Mongo::Connection.new('localhost', 27017, 1, {:reconnect_in => 1})
    #conn.db('http_log').collection('aggregators')
    conn.db("zambosa_#{ Goliath.env.to_s }").collection('UsageInfo')
  end

  filename = File.join(File.dirname(__FILE__), 'config', 'database.yml')
  ActiveRecord::Base.configurations = YAML::load(ERB.new(File.read(filename)).result)
  ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[Goliath.env.to_s])
  ActiveRecord::Base.logger = logger
end
