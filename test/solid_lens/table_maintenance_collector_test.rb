# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/table_maintenance_collector"

class TableMaintenanceCollectorTest < Minitest::Test
  def test_collect_reports_expired_blocked_semaphores_and_stale_claims
    connection = FakeTableConnection.new(
      adapter_name: "SQLite",
      select_values: {
        /COUNT\(\*\) FROM solid_queue_blocked_executions WHERE expires_at <=/ => "2",
        /MIN\(expires_at\) FROM solid_queue_blocked_executions WHERE expires_at <=/ => "2026-06-13 12:31:00",
        /COUNT\(\*\) FROM solid_queue_semaphores WHERE expires_at <=/ => "3",
        /MIN\(expires_at\) FROM solid_queue_semaphores WHERE expires_at <=/ => "2026-06-13 12:30:30",
        /SELECT COUNT\(\*\)\s+FROM solid_queue_semaphores semaphores/ => "1",
        /SELECT MIN\(semaphores\.expires_at\)/ => "2026-06-13 12:29:30",
        /SELECT COUNT\(\*\)\s+FROM solid_queue_claimed_executions claimed/ => "4",
        /SELECT MIN\(\s+CASE\s+WHEN processes\.id IS NULL THEN claimed\.created_at/ => "2026-06-13 12:28:00"
      },
      select_all_rows: {
        /SELECT semaphores\.key/ => [
          {"key" => "account:42"}
        ]
      }
    )

    result = SolidLens::Collectors::TableMaintenanceCollector.new(
      connection: connection,
      now: Time.utc(2026, 6, 13, 12, 34, 30),
      process_alive_threshold: 300
    ).collect(
      existing: %w[
        solid_queue_blocked_executions
        solid_queue_claimed_executions
        solid_queue_processes
        solid_queue_semaphores
      ]
    )

    assert_equal 2, result.fetch(:expired_blocked_execution_count)
    assert_equal 210.0, result.fetch(:oldest_expired_blocked_lag_seconds)
    assert_equal 3, result.fetch(:expired_semaphore_count)
    assert_equal 240.0, result.fetch(:oldest_expired_semaphore_lag_seconds)
    assert_equal 1, result.fetch(:expired_orphan_semaphore_count)
    assert_equal 300.0, result.fetch(:oldest_expired_orphan_semaphore_lag_seconds)
    assert_equal ["account:42"], result.fetch(:expired_orphan_semaphore_keys)
    assert_equal 300, result.fetch(:process_alive_threshold_seconds)
    assert_equal 4, result.fetch(:claimed_by_dead_process_count)
    assert_equal 390.0, result.fetch(:oldest_claimed_dead_lag_seconds)
  end

  def test_collect_returns_defaults_when_maintenance_tables_are_missing
    result = SolidLens::Collectors::TableMaintenanceCollector.new(
      connection: FakeTableConnection.new(adapter_name: "SQLite"),
      now: Time.utc(2026, 6, 13, 12, 34, 30),
      process_alive_threshold: 300
    ).collect(existing: [])

    assert_equal 0, result.fetch(:expired_blocked_execution_count)
    assert_equal 0.0, result.fetch(:oldest_expired_blocked_lag_seconds)
    assert_equal 0, result.fetch(:expired_semaphore_count)
    assert_equal 0.0, result.fetch(:oldest_expired_semaphore_lag_seconds)
    assert_equal 0, result.fetch(:expired_orphan_semaphore_count)
    assert_equal 0.0, result.fetch(:oldest_expired_orphan_semaphore_lag_seconds)
    assert_equal [], result.fetch(:expired_orphan_semaphore_keys)
    assert_equal 300, result.fetch(:process_alive_threshold_seconds)
    assert_equal 0, result.fetch(:claimed_by_dead_process_count)
    assert_equal 0.0, result.fetch(:oldest_claimed_dead_lag_seconds)
  end
end
