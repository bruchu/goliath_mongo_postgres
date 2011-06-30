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
