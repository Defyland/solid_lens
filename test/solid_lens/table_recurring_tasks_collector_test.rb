# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/table_recurring_tasks_collector"

class TableRecurringTasksCollectorTest < Minitest::Test
  def test_collect_flags_overdue_task_without_recent_execution
    connection = FakeTableConnection.new(
      adapter_name: "SQLite",
      select_all_rows: {
        /FROM solid_queue_recurring_tasks/ => [
          {
            "key" => "nightly_cleanup",
            "schedule" => "* * * * *",
            "static" => "0",
            "created_at" => "2026-06-13 12:30:00",
            "last_run_at" => nil
          }
        ]
      }
    )

    result = SolidLens::Collectors::TableRecurringTasksCollector.new(
      connection: connection,
      now: Time.utc(2026, 6, 13, 12, 34, 30)
    ).collect(existing: %w[solid_queue_recurring_tasks solid_queue_recurring_executions])

    assert_equal 1, result.fetch(:overdue_recurring_task_count)
    assert_equal 1, result.fetch(:overdue_dynamic_recurring_task_count)
    assert_equal 0, result.fetch(:overdue_static_recurring_task_count)
    assert_equal ["nightly_cleanup"], result.fetch(:overdue_recurring_task_keys)
    assert_equal 30.0, result.fetch(:oldest_recurring_task_lag_seconds)
  end

  def test_collect_separates_overdue_dynamic_and_static_task_counts
    connection = FakeTableConnection.new(
      adapter_name: "SQLite",
      select_all_rows: {
        /FROM solid_queue_recurring_tasks/ => [
          {
            "key" => "dynamic_cleanup",
            "schedule" => "* * * * *",
            "static" => "0",
            "created_at" => "2026-06-13 12:30:00",
            "last_run_at" => nil
          },
          {
            "key" => "static_cleanup",
            "schedule" => "* * * * *",
            "static" => "1",
            "created_at" => "2026-06-13 12:30:00",
            "last_run_at" => nil
          }
        ]
      }
    )

    result = SolidLens::Collectors::TableRecurringTasksCollector.new(
      connection: connection,
      now: Time.utc(2026, 6, 13, 12, 34, 30)
    ).collect(existing: %w[solid_queue_recurring_tasks solid_queue_recurring_executions])

    assert_equal 2, result.fetch(:overdue_recurring_task_count)
    assert_equal 1, result.fetch(:overdue_dynamic_recurring_task_count)
    assert_equal 1, result.fetch(:overdue_static_recurring_task_count)
  end

  def test_collect_does_not_flag_task_created_after_previous_schedule_boundary
    connection = FakeTableConnection.new(
      adapter_name: "SQLite",
      select_all_rows: {
        /FROM solid_queue_recurring_tasks/ => [
          {
            "key" => "nightly_cleanup",
            "schedule" => "* * * * *",
            "static" => "0",
            "created_at" => "2026-06-13 12:34:15",
            "last_run_at" => nil
          }
        ]
      }
    )

    result = SolidLens::Collectors::TableRecurringTasksCollector.new(
      connection: connection,
      now: Time.utc(2026, 6, 13, 12, 34, 30)
    ).collect(existing: %w[solid_queue_recurring_tasks solid_queue_recurring_executions])

    assert_equal 0, result.fetch(:overdue_recurring_task_count)
    assert_equal 0, result.fetch(:overdue_dynamic_recurring_task_count)
    assert_equal 0, result.fetch(:overdue_static_recurring_task_count)
    assert_empty result.fetch(:overdue_recurring_task_keys)
  end
end
