# frozen_string_literal: true

require_relative "base_check"
require_relative "concurrency_maintenance_support"

module SolidLens
  module Checks
    class SemaphoreHealthCheck < BaseCheck
      include ConcurrencyMaintenanceSupport

      HIGH_ORPHAN_SEMAPHORE_COUNT = 5
      HIGH_ORPHAN_SEMAPHORE_LAG_SECONDS = 300

      def call
        return [] unless expired_semaphore_count.positive?

        findings = []

        if enabled_dispatchers.empty?
          findings << finding(
            id: "solid_queue.semaphores.expired_without_maintenance",
            severity: :high,
            title: "Expired concurrency semaphores have no dispatcher maintenance path",
            evidence: semaphore_evidence.merge(dispatchers: dispatchers),
            recommendation: "Enable concurrency_maintenance on at least one dispatcher. Without it, expired semaphores can keep concurrency-limited jobs throttled until manual cleanup or process restart."
          )
        elsif oldest_expired_semaphore_lag_seconds > fastest_concurrency_maintenance_interval
          findings << finding(
            id: "solid_queue.semaphores.expired_longer_than_maintenance_interval",
            severity: :high,
            title: "Expired concurrency semaphores are older than the dispatcher maintenance interval",
            evidence: semaphore_evidence.merge(
              fastest_concurrency_maintenance_interval_seconds: fastest_concurrency_maintenance_interval,
              enabled_dispatchers: enabled_dispatchers
            ),
            recommendation: "Verify dispatchers are actually running, reduce concurrency_maintenance_interval if semaphore cleanup is too slow, and restore the Solid Queue semaphore cleanup index before trusting concurrency-limited throughput."
          )
        end

        if expired_orphan_semaphore_count.positive?
          findings << finding(
            id: "solid_queue.semaphores.expired_without_blocked_backlog",
            severity: orphan_semaphore_severity,
            title: "Expired concurrency semaphores exist without matching blocked backlog",
            evidence: semaphore_evidence,
            recommendation: "Inspect leaked concurrency keys and dispatcher cleanup. Expired semaphores without matching blocked executions usually indicate stale semaphore rows, not just slow backlog recovery."
          )
        end

        findings
      end

      private

      def semaphore_evidence
        {
          semaphore_count: semaphore_count,
          expired_semaphore_count: expired_semaphore_count,
          blocked_execution_count: blocked_execution_count,
          oldest_expired_semaphore_lag_seconds: oldest_expired_semaphore_lag_seconds,
          expired_orphan_semaphore_count: expired_orphan_semaphore_count,
          oldest_expired_orphan_semaphore_lag_seconds: oldest_expired_orphan_semaphore_lag_seconds,
          expired_orphan_semaphore_keys: expired_orphan_semaphore_keys
        }
      end

      def orphan_semaphore_severity
        return :high if expired_orphan_semaphore_count >= HIGH_ORPHAN_SEMAPHORE_COUNT
        return :high if oldest_expired_orphan_semaphore_lag_seconds >= HIGH_ORPHAN_SEMAPHORE_LAG_SECONDS

        :medium
      end

      def semaphore_count
        tables.fetch(:counts, {}).fetch("solid_queue_semaphores", 0).to_i
      end

      def expired_semaphore_count
        tables.fetch(:expired_semaphore_count, 0).to_i
      end

      def blocked_execution_count
        tables.fetch(:counts, {}).fetch("solid_queue_blocked_executions", 0).to_i
      end

      def oldest_expired_semaphore_lag_seconds
        tables.fetch(:oldest_expired_semaphore_lag_seconds, 0.0).to_f
      end

      def expired_orphan_semaphore_count
        tables.fetch(:expired_orphan_semaphore_count, 0).to_i
      end

      def oldest_expired_orphan_semaphore_lag_seconds
        tables.fetch(:oldest_expired_orphan_semaphore_lag_seconds, 0.0).to_f
      end

      def expired_orphan_semaphore_keys
        Array(tables.fetch(:expired_orphan_semaphore_keys, []))
      end
    end
  end
end
