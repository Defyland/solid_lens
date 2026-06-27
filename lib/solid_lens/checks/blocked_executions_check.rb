# frozen_string_literal: true

require_relative "base_check"
require_relative "concurrency_maintenance_support"

module SolidLens
  module Checks
    class BlockedExecutionsCheck < BaseCheck
      include ConcurrencyMaintenanceSupport

      def call
        return [] unless expired_blocked_execution_count.positive?

        if enabled_dispatchers.empty?
          return [
            finding(
              id: "solid_queue.blocked.expired_without_maintenance",
              severity: :high,
              title: "Expired blocked jobs have no dispatcher maintenance path",
              evidence: blocked_evidence.merge(dispatchers: dispatchers),
              recommendation: "Enable concurrency_maintenance on at least one dispatcher. Without it, expired blocked executions and stale semaphores depend on restarts or manual cleanup instead of automatic recovery."
            )
          ]
        end

        return [] unless oldest_expired_blocked_lag_seconds > fastest_concurrency_maintenance_interval

        [
          finding(
            id: "solid_queue.blocked.expired_longer_than_maintenance_interval",
            severity: :high,
            title: "Expired blocked jobs are older than the dispatcher maintenance interval",
            evidence: blocked_evidence.merge(
              fastest_concurrency_maintenance_interval_seconds: fastest_concurrency_maintenance_interval,
              enabled_dispatchers: enabled_dispatchers
            ),
            recommendation: "Verify dispatchers are actually running, reduce concurrency_maintenance_interval if recovery is too slow, and confirm blocked-job recovery uses the expected indexes via solid_lens:explain."
          )
        ]
      end

      private

      def blocked_evidence
        {
          blocked_execution_count: blocked_execution_count,
          expired_blocked_execution_count: expired_blocked_execution_count,
          blocked_queue_depth_by_queue: tables.fetch(:blocked_queue_depth_by_queue, {}),
          oldest_blocked_age_seconds: tables.fetch(:oldest_blocked_age_seconds, 0.0).to_f,
          oldest_expired_blocked_lag_seconds: oldest_expired_blocked_lag_seconds
        }
      end

      def blocked_execution_count
        tables.fetch(:counts, {}).fetch("solid_queue_blocked_executions", 0).to_i
      end

      def expired_blocked_execution_count
        tables.fetch(:expired_blocked_execution_count, 0).to_i
      end

      def oldest_expired_blocked_lag_seconds
        tables.fetch(:oldest_expired_blocked_lag_seconds, 0.0).to_f
      end
    end
  end
end
