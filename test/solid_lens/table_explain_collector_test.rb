# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/table_explain_collector"

class TableExplainCollectorTest < Minitest::Test
  def test_collect_builds_postgres_queries_with_skip_locked_and_wildcards
    connection = FakeTableConnection.new(
      adapter_name: "PostgreSQL",
      quote_values: {
        "critical" => "'critical'",
        "mailers%" => "'mailers%'",
        "account:42" => "'account:42'"
      },
      select_values: {
        "SELECT concurrency_key FROM solid_queue_blocked_executions ORDER BY concurrency_key ASC LIMIT 1" => "account:42"
      },
      select_all_rows: {
        /EXPLAIN \(FORMAT JSON\) SELECT job_id FROM solid_queue_ready_executions ORDER BY priority ASC, job_id ASC LIMIT 1 FOR UPDATE SKIP LOCKED/ => [{"Plan" => {"Node Type" => "Index Scan"}}],
        /EXPLAIN \(FORMAT JSON\) SELECT job_id FROM solid_queue_ready_executions WHERE queue_name = 'critical' ORDER BY priority ASC, job_id ASC LIMIT 1 FOR UPDATE SKIP LOCKED/ => [{"Plan" => {"Node Type" => "Index Scan"}}],
        /EXPLAIN \(FORMAT JSON\) SELECT DISTINCT\(queue_name\) FROM solid_queue_ready_executions WHERE queue_name LIKE 'mailers%'/ => [{"Plan" => {"Node Type" => "Unique"}}],
        /EXPLAIN \(FORMAT JSON\) SELECT job_id FROM solid_queue_scheduled_executions WHERE scheduled_at <= CURRENT_TIMESTAMP ORDER BY scheduled_at ASC, priority ASC, job_id ASC LIMIT 1 FOR UPDATE SKIP LOCKED/ => [{"Plan" => {"Node Type" => "Index Scan"}}],
        /EXPLAIN \(FORMAT JSON\) SELECT job_id FROM solid_queue_blocked_executions WHERE concurrency_key = 'account:42' ORDER BY priority ASC, job_id ASC LIMIT 1 FOR UPDATE SKIP LOCKED/ => [{"Plan" => {"Node Type" => "Index Scan"}}]
      }
    )

    result = SolidLens::Collectors::TableExplainCollector.new(
      connection: connection,
      queue_config: {
        workers: [{"queues" => ["mailers*", "critical"]}],
        wildcard_queue_specs: ["mailers*"]
      },
      database: {adapter_name: "PostgreSQL", skip_locked_supported: true}
    ).collect(
      existing: %w[solid_queue_ready_executions solid_queue_scheduled_executions solid_queue_blocked_executions],
      paused: [],
      table_counts: {"solid_queue_blocked_executions" => 1}
    )

    assert_equal "postgresql", result.fetch(:poll_all).fetch(:adapter)
    assert_includes result.fetch(:poll_all).fetch(:sql), "FOR UPDATE SKIP LOCKED"
    assert_includes result.fetch(:poll_all).fetch(:explain_sql), "EXPLAIN (FORMAT JSON)"
    assert_includes result.fetch(:discover_wildcard_queues).fetch(:sql), "queue_name LIKE 'mailers%'"
    assert_equal ["index_solid_queue_blocked_executions_for_release"], result.fetch(:release_blocked).fetch(:expected_indexes)
  end

  def test_collect_uses_sqlite_explain_query_plan_and_discovers_all_queues_when_paused
    connection = FakeTableConnection.new(
      adapter_name: "SQLite",
      quote_values: {"default" => "'default'"},
      select_values: {
        "SELECT queue_name FROM solid_queue_ready_executions ORDER BY queue_name ASC LIMIT 1" => "default"
      },
      select_all_rows: {
        /EXPLAIN QUERY PLAN SELECT job_id FROM solid_queue_ready_executions ORDER BY priority ASC, job_id ASC LIMIT 1/ => [{"detail" => "SCAN solid_queue_ready_executions"}],
        /EXPLAIN QUERY PLAN SELECT job_id FROM solid_queue_ready_executions WHERE queue_name = 'default' ORDER BY priority ASC, job_id ASC LIMIT 1/ => [{"detail" => "SEARCH solid_queue_ready_executions"}],
        /EXPLAIN QUERY PLAN SELECT DISTINCT\(queue_name\) FROM solid_queue_ready_executions/ => [{"detail" => "SCAN solid_queue_ready_executions"}]
      }
    )

    result = SolidLens::Collectors::TableExplainCollector.new(
      connection: connection,
      queue_config: {workers: [{"queues" => ["*"]}], wildcard_queue_specs: []},
      database: {adapter_name: "SQLite", skip_locked_supported: false}
    ).collect(
      existing: ["solid_queue_ready_executions"],
      paused: ["mailers"],
      table_counts: {"solid_queue_blocked_executions" => 0}
    )

    assert_equal "sqlite", result.fetch(:poll_all).fetch(:adapter)
    refute_includes result.fetch(:poll_all).fetch(:sql), "FOR UPDATE"
    assert_includes result.fetch(:poll_all).fetch(:explain_sql), "EXPLAIN QUERY PLAN"
    assert result.key?(:discover_all_queues)
  end
end
