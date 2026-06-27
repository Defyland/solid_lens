# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/table_collector"

class TableCollectorTest < Minitest::Test
  def test_collect_returns_unavailable_when_connection_is_missing
    result = SolidLens::Collectors::TableCollector.new(connection: nil).collect

    assert_equal false, result.fetch(:available)
    assert_equal "ActiveRecord connection unavailable", result.fetch(:error)
  end

  def test_collect_returns_inventory_and_backlog_evidence_for_supported_tables
    connection = FakeTableConnection.new(
      adapter_name: "SQLite",
      existing_tables: %w[
        solid_queue_pauses
        solid_queue_ready_executions
        solid_queue_scheduled_executions
      ],
      indexes: {
        "solid_queue_ready_executions" => %w[index_solid_queue_poll_all index_solid_queue_poll_by_queue]
      },
      select_values: {
        /COUNT\(\*\) FROM solid_queue_pauses$/ => "1",
        /COUNT\(\*\) FROM solid_queue_ready_executions$/ => "4",
        /COUNT\(\*\) FROM solid_queue_scheduled_executions$/ => "2",
        "SELECT MIN(created_at) FROM solid_queue_ready_executions" => "2026-06-13 12:33:45",
        /COUNT\(\*\) FROM solid_queue_scheduled_executions WHERE scheduled_at <=/ => "2",
        /MIN\(scheduled_at\) FROM solid_queue_scheduled_executions WHERE scheduled_at <=/ => "2026-06-13 12:33:00"
      },
      select_all_rows: {
        /SELECT queue_name FROM solid_queue_pauses/ => [
          {"queue_name" => "mailers"}
        ],
        /FROM solid_queue_ready_executions/ => [
          {"queue_name" => "mailers", "count" => "4"}
        ]
      }
    )

    result = SolidLens::Collectors::TableCollector.new(
      connection: connection,
      explain: false,
      now: Time.utc(2026, 6, 13, 12, 34, 30),
      scheduled_grace_seconds: 60
    ).collect

    assert_equal true, result.fetch(:available)
    assert_equal(
      %w[solid_queue_pauses solid_queue_ready_executions solid_queue_scheduled_executions],
      result.fetch(:existing_tables)
    )
    assert_includes result.fetch(:missing_tables), "solid_queue_blocked_executions"
    assert_equal 1, result.fetch(:counts).fetch("solid_queue_pauses")
    assert_equal 4, result.fetch(:counts).fetch("solid_queue_ready_executions")
    assert_equal(
      %w[index_solid_queue_poll_all index_solid_queue_poll_by_queue],
      result.fetch(:indexes).fetch("solid_queue_ready_executions")
    )
    assert_equal ["mailers"], result.fetch(:paused_queues)
    assert_equal({"mailers" => 4}, result.fetch(:ready_queue_depth_by_queue))
    assert_equal 45.0, result.fetch(:oldest_ready_age_seconds)
    assert_equal 2, result.fetch(:overdue_scheduled_count)
    assert_equal 90.0, result.fetch(:oldest_scheduled_lag_seconds)
    assert_equal 300, result.fetch(:process_alive_threshold_seconds)
    assert_equal({}, result.fetch(:bloat))
    assert_equal({}, result.fetch(:explains))
    assert_equal 0, result.fetch(:overdue_recurring_task_count)
  end
end
