# frozen_string_literal: true

require "test_helper"

class DatabaseCollectorTest < Minitest::Test
  FakePool = Struct.new(:size)

  class FakeConnection
    attr_reader :adapter_name, :database_version, :pool

    def initialize(adapter_name:, database_version:, server_version:, version_comment:)
      @adapter_name = adapter_name
      @database_version = database_version
      @server_version = server_version
      @version_comment = version_comment
      @pool = FakePool.new(5)
    end

    def active?
      true
    end

    def select_value(sql)
      case sql
      when "SELECT @@version"
        @server_version
      when "SELECT @@version_comment"
        @version_comment
      else
        raise "unexpected SQL: #{sql}"
      end
    end
  end

  def test_mariadb_flavor_uses_server_identity_when_database_version_is_numeric
    evidence = collect_database_evidence(
      FakeConnection.new(
        adapter_name: "Trilogy",
        database_version: "10.5.0",
        server_version: "10.5.0-MariaDB",
        version_comment: "MariaDB Server"
      )
    )

    assert_equal "mariadb", evidence.fetch(:database_flavor)
    assert_equal false, evidence.fetch(:skip_locked_supported)
  end

  private

  def collect_database_evidence(connection)
    collector = SolidLens::Collectors::DatabaseCollector.new
    collector.singleton_class.define_method(:queue_connection) { connection }
    collector.collect.fetch(:evidence)
  end
end
