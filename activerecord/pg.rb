#!/usr/bin/env ruby

# gem install activerecord
# gem install mysql2

# create database goliath_test
# create user 'goliath'@'localhost' identified by 'goliath'
# grant all on goliath_test.* to 'goliath'@'localhost'
# create table users (id int not null auto_increment primary key, name varchar(255), email varchar(255));
# insert into users (name, email) values ('dan', 'dj2@everyburning.com'), ('Ilya', 'ilya@igvita.com');

$: << "../../lib" << "./lib"

require 'bundler/setup'
require 'goliath'
require 'active_record'
require 'yajl'

require 'postgres-pr/postgres-compat'

class PGresult
  alias :nfields :num_fields
  alias :ntuples :num_tuples
  alias :ftype :type
end

require 'active_record'
require 'active_record/connection_adapters/postgresql_adapter'
require 'active_record/patches'

module ActiveRecord
  module ConnectionAdapters
    class EmPostgreSQLAdapter < PostgreSQLAdapter
      def supports_standard_conforming_strings?
        # Temporarily set the client message level above error to prevent unintentional
        # error messages in the logs when working on a PostgreSQL database server that
        # does not support standard conforming strings.
        client_min_messages_old = client_min_messages
        self.client_min_messages = 'panic'

        # postgres-pr does not raise an exception when client_min_messages is set higher
        # than error and "SHOW standard_conforming_strings" fails, but returns an empty
        # PGresult instead.
        has_support = query('SHOW standard_conforming_strings')[0][0] rescue false
        self.client_min_messages = client_min_messages_old
        has_support
      end
    end
  end
end

class User < ActiveRecord::Base
end

class Pg < Goliath::API
  use Goliath::Rack::Params
  use Goliath::Rack::DefaultMimeType
  use Goliath::Rack::Formatters::JSON
  use Goliath::Rack::Render

  use Goliath::Rack::Validation::RequiredParam, {:key => 'id', :type => 'ID'}
  use Goliath::Rack::Validation::NumericRange, {:key => 'id', :min => 1}

  def response(env)
    #User.find_by_sql("SELECT PG_SLEEP(10)")
    [200, {}, User.find(params['id'])]
  end
end
