# frozen_string_literal: true

require "fugit"
require "time"
require_relative "timestamp_support"

module SolidLens
  module Collectors
    class TableRecurringTasksCollector
      include TimestampSupport

      SAMPLE_LIMIT = 5

      def initialize(connection:, now:)
        @connection = connection
        @now = now
      end

      def collect(existing:)
        return default_evidence unless recurring_tasks_supported?(existing)

        overdue_tasks = recurring_task_rows.filter_map { |row| overdue_task(row) }
          .sort_by { |task| [-task.fetch(:lag_seconds), task.fetch(:key)] }

        default_evidence.merge(
          recurring_task_count: recurring_task_rows.size,
          dynamic_recurring_task_count: recurring_task_rows.count { |row| !static_task?(row) },
          overdue_recurring_task_count: overdue_tasks.size,
          overdue_dynamic_recurring_task_count: overdue_tasks.count { |task| !task.fetch(:static) },
          overdue_static_recurring_task_count: overdue_tasks.count { |task| task.fetch(:static) },
          oldest_recurring_task_lag_seconds: overdue_tasks.map { |task| task.fetch(:lag_seconds) }.max.to_f.round(3),
          overdue_recurring_task_keys: overdue_tasks.first(SAMPLE_LIMIT).map { |task| task.fetch(:key) },
          overdue_recurring_tasks: overdue_tasks.first(SAMPLE_LIMIT)
        )
      rescue => error
        default_evidence.merge(recurring_tasks_error: "#{error.class}: #{error.message}")
      end

      private

      attr_reader :connection, :now

      def default_evidence
        {
          recurring_task_count: 0,
          dynamic_recurring_task_count: 0,
          overdue_recurring_task_count: 0,
          overdue_dynamic_recurring_task_count: 0,
          overdue_static_recurring_task_count: 0,
          oldest_recurring_task_lag_seconds: 0.0,
          overdue_recurring_task_keys: [],
          overdue_recurring_tasks: []
        }
      end

      def recurring_tasks_supported?(existing)
        %w[solid_queue_recurring_tasks solid_queue_recurring_executions].all? { |table| existing.include?(table) }
      end

      def recurring_task_rows
        @recurring_task_rows ||= rows(<<~SQL)
          SELECT tasks.key, tasks.schedule, tasks.static, tasks.created_at, MAX(executions.run_at) AS last_run_at
          FROM solid_queue_recurring_tasks tasks
          LEFT JOIN solid_queue_recurring_executions executions
            ON executions.task_key = tasks.key
          GROUP BY tasks.key, tasks.schedule, tasks.static, tasks.created_at
          ORDER BY tasks.key ASC
        SQL
      end

      def overdue_task(row)
        expected_run_at = Fugit.parse(row.fetch("schedule"), multi: :fail).previous_time(now).utc
        created_at = parse_timestamp(row.fetch("created_at"))
        last_run_at = parse_timestamp(row["last_run_at"])

        return if created_at > expected_run_at
        return if last_run_at && last_run_at >= expected_run_at

        {
          key: row.fetch("key"),
          static: static_task?(row),
          schedule: row.fetch("schedule"),
          created_at: created_at.utc.iso8601,
          last_run_at: last_run_at&.utc&.iso8601,
          expected_run_at: expected_run_at.iso8601,
          lag_seconds: timestamp_age_seconds(now: now, value: expected_run_at)
        }
      end

      def static_task?(row)
        value = row.fetch("static")
        value == true || value.to_s == "true" || value.to_s == "1"
      end

      def parse_timestamp(value)
        return if value.nil?
        return value if value.is_a?(Time)
        return value.to_time if value.is_a?(DateTime)

        string_value = value.to_s
        return Time.parse(string_value) if string_value.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/)
        return Time.parse(string_value) if active_record_default_timezone == :local

        Time.parse("#{string_value} UTC")
      end

      def rows(sql)
        connection.select_all(sql).to_a.map { |row| row.stringify_keys }
      end
    end
  end
end
