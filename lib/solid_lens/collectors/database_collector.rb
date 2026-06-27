# frozen_string_literal: true

module SolidLens
  module Collectors
    class DatabaseCollector
      def collect
        connection = queue_connection
        evidence = base_evidence(connection)
        evidence[:skip_locked_supported] = skip_locked_supported?(evidence)

        {connection: connection, evidence: evidence}
      rescue => error
        {
          connection: nil,
          evidence: {
            connected: false,
            error: "#{error.class}: #{error.message}",
            skip_locked_supported: nil
          }
        }
      end

      private

      def queue_connection
        if defined?(SolidQueue::Record)
          SolidQueue::Record.connection
        elsif defined?(ActiveRecord::Base)
          ActiveRecord::Base.connection
        end
      end

      def base_evidence(connection)
        return {connected: false, error: "ActiveRecord connection unavailable"} unless connection

        adapter_name = connection.adapter_name.to_s
        version = database_version(connection)
        server_identity = database_server_identity(connection, adapter_name)

        {
          connected: connected?(connection),
          adapter_name: adapter_name,
          database_version: version,
          database_flavor: database_flavor(adapter_name, version, server_identity),
          database_server_identity: server_identity,
          connection_pool_size: connection.pool.size
        }.compact
      end

      def database_version(connection)
        if connection.respond_to?(:database_version)
          connection.database_version.to_s
        elsif connection.adapter_name.downcase.include?("sqlite")
          connection.select_value("SELECT sqlite_version()").to_s
        else
          connection.select_value("SELECT VERSION()").to_s
        end
      rescue => error
        "unknown: #{error.class}: #{error.message}"
      end

      def database_server_identity(connection, adapter_name)
        return unless adapter_name.downcase.match?(/mysql|trilogy/)

        [connection.select_value("SELECT @@version"), connection.select_value("SELECT @@version_comment")].compact.join(" ")
      rescue
        nil
      end

      def database_flavor(adapter_name, version, server_identity)
        identity = [adapter_name, version, server_identity].compact.join(" ").downcase

        return "postgresql" if identity.include?("postgres")
        return "sqlite" if identity.include?("sqlite")
        return "mariadb" if identity.include?("mariadb")
        "mysql" if identity.match?(/mysql|trilogy/)
      end

      def skip_locked_supported?(evidence)
        adapter = evidence[:adapter_name].to_s.downcase
        version = evidence[:database_version].to_s
        flavor = evidence[:database_flavor].to_s

        return version_at_least?(version, 9, 5) if adapter.include?("postgres")
        return version_at_least?(version, 10, 6) if flavor == "mariadb"
        return version_at_least?(version, 8, 0) if adapter.match?(/mysql|trilogy/)
        return false if adapter.include?("sqlite")

        nil
      end

      def version_at_least?(version, major, minor)
        found = version.scan(/\d+/).first(2).map(&:to_i)
        return nil if found.empty?

        (found <=> [major, minor]) >= 0
      end

      def connected?(connection)
        active = connection.active?
        return true if active != false

        connection.select_value("SELECT 1").to_s == "1"
      rescue
        false
      end
    end
  end
end
