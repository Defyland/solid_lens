# frozen_string_literal: true

require_relative "timestamp_support"

module SolidLens
  module Collectors
    class TableMaintenanceCollector
      include TimestampSupport

      def initialize(connection:, now:, process_alive_threshold:)
        @connection = connection
        @now = now
        @process_alive_threshold = process_alive_threshold
      end

      def collect(existing:)
        {
          expired_blocked_execution_count: expired_blocked_execution_count(existing),
          oldest_expired_blocked_lag_seconds: oldest_expired_blocked_lag_seconds(existing),
          expired_semaphore_count: expired_semaphore_count(existing),
          oldest_expired_semaphore_lag_seconds: oldest_expired_semaphore_lag_seconds(existing),
          expired_orphan_semaphore_count: expired_orphan_semaphore_count(existing),
          oldest_expired_orphan_semaphore_lag_seconds: oldest_expired_orphan_semaphore_lag_seconds(existing),
          expired_orphan_semaphore_keys: expired_orphan_semaphore_keys(existing),
          process_alive_threshold_seconds: process_alive_threshold.to_i,
          claimed_by_dead_process_count: claimed_by_dead_process_count(existing),
          oldest_claimed_dead_lag_seconds: oldest_claimed_dead_lag_seconds(existing)
        }
      end

      private

      attr_reader :connection, :now, :process_alive_threshold

      def expired_blocked_execution_count(existing)
        return 0 unless existing.include?("solid_queue_blocked_executions")

        select_count("solid_queue_blocked_executions", "expires_at <= #{quoted_now}")
      end

      def oldest_expired_blocked_lag_seconds(existing)
        return 0.0 unless existing.include?("solid_queue_blocked_executions")

        timestamp_age_seconds(
          now: now,
          value: connection.select_value("SELECT MIN(expires_at) FROM solid_queue_blocked_executions WHERE expires_at <= #{quoted_now}")
        )
      end

      def expired_semaphore_count(existing)
        return 0 unless existing.include?("solid_queue_semaphores")

        select_count("solid_queue_semaphores", "expires_at <= #{quoted_now}")
      end

      def oldest_expired_semaphore_lag_seconds(existing)
        return 0.0 unless existing.include?("solid_queue_semaphores")

        timestamp_age_seconds(
          now: now,
          value: connection.select_value("SELECT MIN(expires_at) FROM solid_queue_semaphores WHERE expires_at <= #{quoted_now}")
        )
      end

      def expired_orphan_semaphore_count(existing)
        return 0 unless orphan_semaphore_supported?(existing)

        connection.select_value(<<~SQL).to_i
          SELECT COUNT(*)
          FROM solid_queue_semaphores semaphores
          LEFT JOIN solid_queue_blocked_executions blocked
            ON blocked.concurrency_key = semaphores.key
          WHERE semaphores.expires_at <= #{quoted_now}
            AND blocked.id IS NULL
        SQL
      end

      def oldest_expired_orphan_semaphore_lag_seconds(existing)
        return 0.0 unless orphan_semaphore_supported?(existing)

        timestamp_age_seconds(now: now, value: connection.select_value(<<~SQL))
          SELECT MIN(semaphores.expires_at)
          FROM solid_queue_semaphores semaphores
          LEFT JOIN solid_queue_blocked_executions blocked
            ON blocked.concurrency_key = semaphores.key
          WHERE semaphores.expires_at <= #{quoted_now}
            AND blocked.id IS NULL
        SQL
      end

      def expired_orphan_semaphore_keys(existing)
        return [] unless orphan_semaphore_supported?(existing)

        rows(<<~SQL).map { |row| row.fetch("key") }
          SELECT semaphores.key
          FROM solid_queue_semaphores semaphores
          LEFT JOIN solid_queue_blocked_executions blocked
            ON blocked.concurrency_key = semaphores.key
          WHERE semaphores.expires_at <= #{quoted_now}
            AND blocked.id IS NULL
          ORDER BY semaphores.expires_at ASC, semaphores.key ASC
          LIMIT 5
        SQL
      end

      def claimed_by_dead_process_count(existing)
        required = %w[solid_queue_claimed_executions solid_queue_processes]
        return 0 unless (required - existing).empty?

        connection.select_value(<<~SQL).to_i
          SELECT COUNT(*)
          FROM solid_queue_claimed_executions claimed
          LEFT JOIN solid_queue_processes processes
            ON processes.id = claimed.process_id
          WHERE processes.id IS NULL
             OR processes.last_heartbeat_at < #{quoted_process_cutoff}
        SQL
      end

      def oldest_claimed_dead_lag_seconds(existing)
        required = %w[solid_queue_claimed_executions solid_queue_processes]
        return 0.0 unless (required - existing).empty?

        timestamp_age_seconds(now: now, value: connection.select_value(<<~SQL))
          SELECT MIN(
            CASE
              WHEN processes.id IS NULL THEN claimed.created_at
              ELSE processes.last_heartbeat_at
            END
          )
          FROM solid_queue_claimed_executions claimed
          LEFT JOIN solid_queue_processes processes
            ON processes.id = claimed.process_id
          WHERE processes.id IS NULL
             OR processes.last_heartbeat_at < #{quoted_process_cutoff}
        SQL
      end

      def orphan_semaphore_supported?(existing)
        %w[solid_queue_semaphores solid_queue_blocked_executions].all? { |table| existing.include?(table) }
      end

      def quoted_now
        @quoted_now ||= connection.quote(now)
      end

      def quoted_process_cutoff
        @quoted_process_cutoff ||= connection.quote(now - process_alive_threshold)
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
