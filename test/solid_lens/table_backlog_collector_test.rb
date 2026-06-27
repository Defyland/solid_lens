# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/table_backlog_collector"

class TableBacklogCollectorTest < Minitest::Test
  def test_collect_reports_queue_depths_pauses_and_overdue_scheduled_executions
    connection = FakeTableConnection.new(
      adapter_name: "SQLite",
      select_values: {
        "SELECT MIN(created_at) FROM solid_queue_ready_executions" => "2026-06-13 12:33:45",
        "SELECT MIN(created_at) FROM solid_queue_blocked_executions" => "2026-06-13 12:32:30",
        /COUNT\(\*\) FROM solid_queue_scheduled_executions WHERE scheduled_at <=/ => "2",
        /MIN\(scheduled_at\) FROM solid_queue_scheduled_executions WHERE scheduled_at <=/ => "2026-06-13 12:33:00"
      },
      select_all_rows: {
        /SELECT queue_name FROM solid_queue_pauses/ => [
          {"queue_name" => "critical"},
          {"queue_name" => "mailers"}
        ],
        /FROM solid_queue_ready_executions/ => [
          {"queue_name" => "mailers", "count" => "3"},
          {"queue_name" => "default", "count" => "1"}
        ],
        /FROM solid_queue_blocked_executions/ => [
          {"queue_name" => "critical", "count" => "2"}
        ]
      }
    )

    result = SolidLens::Collectors::TableBacklogCollector.new(
      connection: connection,
      now: Time.utc(2026, 6, 13, 12, 34, 30),
      scheduled_grace_seconds: 60
    ).collect(
      existing: %w[
        solid_queue_pauses
        solid_queue_ready_executions
        solid_queue_blocked_executions
        solid_queue_scheduled_executions
      ]
    )

    assert_equal ["critical", "mailers"], result.fetch(:paused_queues)
    assert_equal({"mailers" => 3, "default" => 1}, result.fetch(:ready_queue_depth_by_queue))
    assert_equal({"critical" => 2}, result.fetch(:blocked_queue_depth_by_queue))
    assert_equal 45.0, result.fetch(:oldest_ready_age_seconds)
    assert_equal 120.0, result.fetch(:oldest_blocked_age_seconds)
    assert_equal 60, result.fetch(:overdue_scheduled_grace_seconds)
    assert_equal 2, result.fetch(:overdue_scheduled_count)
    assert_equal 90.0, result.fetch(:oldest_scheduled_lag_seconds)
  end

  def test_collect_returns_defaults_when_backlog_tables_are_missing
    result = SolidLens::Collectors::TableBacklogCollector.new(
      connection: FakeTableConnection.new(adapter_name: "SQLite"),
      now: Time.utc(2026, 6, 13, 12, 34, 30),
      scheduled_grace_seconds: 60
    ).collect(existing: [])

    assert_equal [], result.fetch(:paused_queues)
    assert_equal({}, result.fetch(:ready_queue_depth_by_queue))
    assert_equal 0.0, result.fetch(:oldest_ready_age_seconds)
    assert_equal({}, result.fetch(:blocked_queue_depth_by_queue))
    assert_equal 0.0, result.fetch(:oldest_blocked_age_seconds)
    assert_equal 60, result.fetch(:overdue_scheduled_grace_seconds)
    assert_equal 0, result.fetch(:overdue_scheduled_count)
    assert_equal 0.0, result.fetch(:oldest_scheduled_lag_seconds)
  end
end
