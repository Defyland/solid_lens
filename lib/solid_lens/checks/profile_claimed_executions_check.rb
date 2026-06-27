# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class ProfileClaimedExecutionsCheck < BaseCheck
      def call
        claimed = profile.fetch(:claimed_execution_health, {})
        peak_dead_count = claimed.fetch(:peak_dead_count, 0).to_i
        finish_dead_count = claimed.fetch(:finish_dead_count, 0).to_i
        dead_count_delta = claimed.fetch(:dead_count_delta, 0).to_i
        peak_oldest_dead_lag = claimed.fetch(:peak_oldest_dead_lag_seconds, 0).to_f
        finish_oldest_dead_lag = claimed.fetch(:finish_oldest_dead_lag_seconds, 0).to_f
        oldest_dead_lag_delta = claimed.fetch(:oldest_dead_lag_delta_seconds, 0).to_f

        return [] unless peak_dead_count.positive?
        return [] unless dead_count_delta.positive? || oldest_dead_lag_delta.positive? ||
          peak_dead_count > finish_dead_count || peak_oldest_dead_lag > finish_oldest_dead_lag

        [
          finding(
            id: "solid_queue.profile.claimed.dead_process.growing",
            severity: :high,
            title: "Dead-process claimed executions accumulated during the profile window",
            evidence: claimed,
            recommendation: "Investigate worker exits, heartbeat staleness, and process pruning before dead claimed executions strand more jobs."
          )
        ]
      end
    end
  end
end
