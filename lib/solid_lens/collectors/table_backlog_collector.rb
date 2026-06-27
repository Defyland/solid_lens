# frozen_string_literal: true

require_relative "timestamp_support"

module SolidLens
  module Collectors
    class TableBacklogCollector
      include TimestampSupport

      def initialize(connection:, now:, scheduled_grace_seconds:)
        @connection = connection
        @now = now
        @scheduled_grace_seconds = scheduled_grace_seconds
      end

      def collect(existing:)
        {
          paused_queues: paused_queues(existing),
          ready_queue_depth_by_queue: ready_queue_depth_by_queue(existing),
          oldest_ready_age_seconds: oldest_ready_age_seconds(existing),
          blocked_queue_depth_by_queue: blocked_queue_depth_by_queue(existing),
          oldest_blocked_age_seconds: oldest_blocked_age_seconds(existing),
          overdue_scheduled_grace_seconds: scheduled_grace_seconds,
          overdue_scheduled_count: overdue_scheduled_count(existing),
          oldest_scheduled_lag_seconds: oldest_scheduled_lag_seconds(existing)
        }
      end

      private

      attr_reader :connection, :now, :scheduled_grace_seconds

      def paused_queues(existing)
        return [] unless existing.include?("solid_queue_pauses")

        rows("SELECT queue_name FROM solid_queue_pauses ORDER BY queue_name").map { |row| row.fetch("queue_name") }
      end

      def ready_queue_depth_by_queue(existing)
        return {} unless existing.include?("solid_queue_ready_executions")

        rows(<<~SQL).to_h do |row|
          SELECT queue_name, COUNT(*) AS count
          FROM solid_queue_ready_executions
          GROUP BY queue_name
          ORDER BY COUNT(*) DESC, queue_name ASC
        SQL
          [row.fetch("queue_name"), row.fetch("count").to_i]
        end
      end

      def oldest_ready_age_seconds(existing)
        return 0.0 unless existing.include?("solid_queue_ready_executions")

        timestamp_age_seconds(
          now: now,
          value: connection.select_value("SELECT MIN(created_at) FROM solid_queue_ready_executions")
        )
      end

      def blocked_queue_depth_by_queue(existing)
        return {} unless existing.include?("solid_queue_blocked_executions")

        rows(<<~SQL).to_h do |row|
          SELECT queue_name, COUNT(*) AS count
          FROM solid_queue_blocked_executions
          GROUP BY queue_name
          ORDER BY COUNT(*) DESC, queue_name ASC
        SQL
          [row.fetch("queue_name"), row.fetch("count").to_i]
        end
      end

      def oldest_blocked_age_seconds(existing)
        return 0.0 unless existing.include?("solid_queue_blocked_executions")

        timestamp_age_seconds(
          now: now,
          value: connection.select_value("SELECT MIN(created_at) FROM solid_queue_blocked_executions")
        )
      end

      def overdue_scheduled_count(existing)
        return 0 unless existing.include?("solid_queue_scheduled_executions")

        cutoff = connection.quote(now - scheduled_grace_seconds)
        select_count("solid_queue_scheduled_executions", "scheduled_at <= #{cutoff}")
      end

      def oldest_scheduled_lag_seconds(existing)
        return 0.0 unless existing.include?("solid_queue_scheduled_executions")

        cutoff = connection.quote(now - scheduled_grace_seconds)
        timestamp_age_seconds(
          now: now,
          value: connection.select_value("SELECT MIN(scheduled_at) FROM solid_queue_scheduled_executions WHERE scheduled_at <= #{cutoff}")
        )
      end

      def select_count(table, where = nil)
        sql = "SELECT COUNT(*) FROM #{table}"
        sql << " WHERE #{where}" if where
        connection.select_value(sql).to_i
      end

      def rows(sql)
        connection.select_all(sql).to_a.map { |row| row.stringify_keys }
      end
    end
  end
end
