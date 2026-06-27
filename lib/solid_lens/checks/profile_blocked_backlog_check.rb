# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class ProfileBlockedBacklogCheck < BaseCheck
      HIGH_BLOCKED_DELTA = 10
      HIGH_BLOCKED_DEPTH = 25
      HIGH_EXPIRED_BLOCKED_DELTA = 5
      HIGH_EXPIRED_BLOCKED_LAG_GROWTH_SECONDS = 30

      def call
        blocked = profile.fetch(:blocked_backlog, {})
        peak_count = blocked.fetch(:peak_count, 0).to_i
        finish_count = blocked.fetch(:finish_count, 0).to_i
        peak_expired_count = blocked.fetch(:peak_expired_count, 0).to_i
        finish_expired_count = blocked.fetch(:finish_expired_count, 0).to_i
        count_delta = blocked.fetch(:count_delta, 0).to_i
        expired_count_delta = blocked.fetch(:expired_count_delta, 0).to_i
        peak_oldest_age = blocked.fetch(:peak_oldest_age_seconds, 0).to_f
        finish_oldest_age = blocked.fetch(:finish_oldest_age_seconds, 0).to_f
        peak_expired_lag = blocked.fetch(:peak_oldest_expired_lag_seconds, 0).to_f
        finish_expired_lag = blocked.fetch(:finish_oldest_expired_lag_seconds, 0).to_f
        oldest_age_delta = blocked.fetch(:oldest_age_delta_seconds, 0).to_f
        oldest_expired_lag_delta = blocked.fetch(:oldest_expired_lag_delta_seconds, 0).to_f

        return [] unless peak_count.positive? || peak_expired_count.positive?
        return [] unless count_delta.positive? || expired_count_delta.positive? ||
          oldest_age_delta.positive? || oldest_expired_lag_delta.positive? ||
          peak_count > finish_count || peak_expired_count > finish_expired_count ||
          peak_oldest_age > finish_oldest_age || peak_expired_lag > finish_expired_lag

        [
          finding(
            id: "solid_queue.profile.blocked_backlog.growing",
            severity: severity_for(blocked),
            title: "Blocked execution backlog or expired blocked lag grew during the profile window",
            evidence: blocked,
            recommendation: "Inspect concurrency hotspots, lower concurrency_maintenance_interval when recovery is too slow, and review concurrency_duration plus worker throughput for the queues with the highest blocked peak."
          )
        ]
      end

      private

      def severity_for(blocked)
        peak_count_delta = blocked.fetch(:peak_count, 0).to_i - blocked.fetch(:start_count, 0).to_i
        peak_expired_delta = blocked.fetch(:peak_expired_count, 0).to_i - blocked.fetch(:start_expired_count, 0).to_i
        peak_expired_lag_delta = blocked.fetch(:peak_oldest_expired_lag_seconds, 0).to_f - blocked.fetch(:start_oldest_expired_lag_seconds, 0).to_f

        return :high if peak_count_delta >= HIGH_BLOCKED_DELTA
        return :high if blocked.fetch(:peak_count, 0).to_i >= HIGH_BLOCKED_DEPTH
        return :high if peak_expired_delta >= HIGH_EXPIRED_BLOCKED_DELTA
        return :high if peak_expired_lag_delta >= HIGH_EXPIRED_BLOCKED_LAG_GROWTH_SECONDS

        :medium
      end
    end
  end
end
