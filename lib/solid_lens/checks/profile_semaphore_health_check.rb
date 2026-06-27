# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class ProfileSemaphoreHealthCheck < BaseCheck
      HIGH_EXPIRED_SEMAPHORE_DELTA = 5
      HIGH_EXPIRED_SEMAPHORE_DEPTH = 20
      HIGH_EXPIRED_SEMAPHORE_LAG_GROWTH_SECONDS = 30
      HIGH_EXPIRED_ORPHAN_SEMAPHORE_DELTA = 3
      HIGH_EXPIRED_ORPHAN_SEMAPHORE_DEPTH = 10
      HIGH_EXPIRED_ORPHAN_SEMAPHORE_LAG_GROWTH_SECONDS = 30

      def call
        semaphores = profile.fetch(:semaphore_health, {})
        findings = []

        if expired_semaphore_growth?(semaphores)
          findings << finding(
            id: "solid_queue.profile.semaphores.expired_growing",
            severity: expired_semaphore_severity_for(semaphores),
            title: "Expired concurrency semaphores accumulated during the profile window",
            evidence: semaphores,
            recommendation: "Verify dispatcher concurrency maintenance is keeping up, inspect stuck concurrency keys, and reduce maintenance latency before expired semaphores suppress throughput."
          )
        end

        if orphan_semaphore_growth?(semaphores)
          findings << finding(
            id: "solid_queue.profile.semaphores.orphaned_growing",
            severity: orphan_semaphore_severity_for(semaphores),
            title: "Expired orphan semaphores accumulated during the profile window",
            evidence: semaphores,
            recommendation: "Inspect leaked concurrency keys and semaphore cleanup. Orphan semaphores that grow over the profile window usually indicate stale rows rather than blocked jobs waiting to be released."
          )
        end

        findings
      end

      private

      def expired_semaphore_growth?(semaphores)
        peak_expired_count = semaphores.fetch(:peak_expired_count, 0).to_i
        finish_expired_count = semaphores.fetch(:finish_expired_count, 0).to_i
        expired_count_delta = semaphores.fetch(:expired_count_delta, 0).to_i
        peak_oldest_lag = semaphores.fetch(:peak_oldest_expired_lag_seconds, 0).to_f
        finish_oldest_lag = semaphores.fetch(:finish_oldest_expired_lag_seconds, 0).to_f
        oldest_lag_delta = semaphores.fetch(:oldest_expired_lag_delta_seconds, 0).to_f

        return false unless peak_expired_count.positive?

        expired_count_delta.positive? || oldest_lag_delta.positive? ||
          peak_expired_count > finish_expired_count || peak_oldest_lag > finish_oldest_lag
      end

      def expired_semaphore_severity_for(semaphores)
        peak_expired_delta = semaphores.fetch(:peak_expired_count, 0).to_i - semaphores.fetch(:start_expired_count, 0).to_i
        peak_lag_delta = semaphores.fetch(:peak_oldest_expired_lag_seconds, 0).to_f - semaphores.fetch(:start_oldest_expired_lag_seconds, 0).to_f

        return :high if peak_expired_delta >= HIGH_EXPIRED_SEMAPHORE_DELTA
        return :high if semaphores.fetch(:peak_expired_count, 0).to_i >= HIGH_EXPIRED_SEMAPHORE_DEPTH
        return :high if peak_lag_delta >= HIGH_EXPIRED_SEMAPHORE_LAG_GROWTH_SECONDS

        :medium
      end

      def orphan_semaphore_growth?(semaphores)
        peak_orphan_count = semaphores.fetch(:peak_expired_orphan_count, 0).to_i
        finish_orphan_count = semaphores.fetch(:finish_expired_orphan_count, 0).to_i
        orphan_count_delta = semaphores.fetch(:expired_orphan_count_delta, 0).to_i
        peak_oldest_orphan_lag = semaphores.fetch(:peak_oldest_expired_orphan_lag_seconds, 0).to_f
        finish_oldest_orphan_lag = semaphores.fetch(:finish_oldest_expired_orphan_lag_seconds, 0).to_f
        oldest_orphan_lag_delta = semaphores.fetch(:oldest_expired_orphan_lag_delta_seconds, 0).to_f

        return false unless peak_orphan_count.positive?

        orphan_count_delta.positive? || oldest_orphan_lag_delta.positive? ||
          peak_orphan_count > finish_orphan_count || peak_oldest_orphan_lag > finish_oldest_orphan_lag
      end

      def orphan_semaphore_severity_for(semaphores)
        peak_orphan_delta = semaphores.fetch(:peak_expired_orphan_count, 0).to_i - semaphores.fetch(:start_expired_orphan_count, 0).to_i
        peak_orphan_lag_delta = semaphores.fetch(:peak_oldest_expired_orphan_lag_seconds, 0).to_f - semaphores.fetch(:start_oldest_expired_orphan_lag_seconds, 0).to_f

        return :high if peak_orphan_delta >= HIGH_EXPIRED_ORPHAN_SEMAPHORE_DELTA
        return :high if semaphores.fetch(:peak_expired_orphan_count, 0).to_i >= HIGH_EXPIRED_ORPHAN_SEMAPHORE_DEPTH
        return :high if peak_orphan_lag_delta >= HIGH_EXPIRED_ORPHAN_SEMAPHORE_LAG_GROWTH_SECONDS

        :medium
      end
    end
  end
end
