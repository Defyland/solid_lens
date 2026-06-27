# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/table_bloat_collector"

class TableBloatCollectorTest < Minitest::Test
  def test_collect_returns_postgres_bloat_stats
    connection = FakeTableConnection.new(
      adapter_name: "PostgreSQL",
      quote_values: {"solid_queue_ready_executions" => "'solid_queue_ready_executions'"},
      select_all_rows: {
        /FROM pg_stat_user_tables/ => [
          {"relname" => "solid_queue_ready_executions", "n_live_tup" => "100", "n_dead_tup" => "25"}
        ]
      }
    )

    result = SolidLens::Collectors::TableBloatCollector.new(connection: connection).collect(
      existing: ["solid_queue_ready_executions"]
    )

    assert_equal 100, result.fetch("solid_queue_ready_executions").fetch(:live_tuples)
    assert_equal 25, result.fetch("solid_queue_ready_executions").fetch(:dead_tuples)
    assert_equal 0.2, result.fetch("solid_queue_ready_executions").fetch(:dead_tuple_ratio)
  end

  def test_collect_returns_empty_hash_for_non_postgres_connections
    connection = FakeTableConnection.new(adapter_name: "SQLite")

    result = SolidLens::Collectors::TableBloatCollector.new(connection: connection).collect(
      existing: ["solid_queue_ready_executions"]
    )

    assert_equal({}, result)
  end

  def test_collect_sorts_tables_for_deterministic_reports
    connection = FakeTableConnection.new(
      adapter_name: "PostgreSQL",
      quote_values: {
        "solid_queue_ready_executions" => "'solid_queue_ready_executions'",
        "solid_queue_blocked_executions" => "'solid_queue_blocked_executions'"
      },
      select_all_rows: {
        /FROM pg_stat_user_tables/ => [
          {"relname" => "solid_queue_ready_executions", "n_live_tup" => "100", "n_dead_tup" => "25"},
          {"relname" => "solid_queue_blocked_executions", "n_live_tup" => "50", "n_dead_tup" => "10"}
        ]
      }
    )

    result = SolidLens::Collectors::TableBloatCollector.new(connection: connection).collect(
      existing: %w[solid_queue_ready_executions solid_queue_blocked_executions]
    )

    assert_equal %w[solid_queue_blocked_executions solid_queue_ready_executions], result.keys
  end
end
