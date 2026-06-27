# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class ClaimedExecutionsCheck < BaseCheck
      def call
        count = tables.fetch(:claimed_by_dead_process_count, 0).to_i
        return [] if count.zero?

        [
          finding(
            id: "solid_queue.claimed.dead_process",
            severity: :high,
            title: "Jobs are claimed by a dead or missing process",
            evidence: {
              claimed_by_dead_process_count: count,
              oldest_claimed_dead_lag_seconds: tables.fetch(:oldest_claimed_dead_lag_seconds, 0.0).to_f,
              process_alive_threshold_seconds: tables.fetch(:process_alive_threshold_seconds, nil)
            },
            recommendation: "Inspect Solid Queue process pruning and heartbeat settings, then fail or release the affected claimed executions deliberately."
          )
        ]
      end
    end
  end
end
