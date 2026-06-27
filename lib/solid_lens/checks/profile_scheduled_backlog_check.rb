# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class ProfileScheduledBacklogCheck < BaseCheck
      HIGH_OVERDUE_DELTA = 10
      HIGH_OVERDUE_DEPTH = 50
      HIGH_LAG_GROWTH_SECONDS = 30

      def call
        scheduled = profile.fetch(:scheduled_backlog, {})
        peak_overdue_count = scheduled.fetch(:peak_overdue_count, 0).to_i
        finish_overdue_count = scheduled.fetch(:finish_overdue_count, 0).to_i
        overdue_count_delta = scheduled.fetch(:overdue_count_delta, 0).to_i
        peak_oldest_lag = scheduled.fetch(:peak_oldest_lag_seconds, 0).to_f
        finish_oldest_lag = scheduled.fetch(:finish_oldest_lag_seconds, 0).to_f
        oldest_lag_delta = scheduled.fetch(:oldest_lag_delta_seconds, 0).to_f

        return [] unless peak_overdue_count.positive?
        return [] unless overdue_count_delta.positive? || oldest_lag_delta.positive? || peak_overdue_count > finish_overdue_count || peak_oldest_lag > finish_oldest_lag

        [
          finding(
            id: "solid_queue.profile.scheduled_backlog.growing",
            severity: severity_for(scheduled),
            title: "Scheduled backlog or dispatch lag grew or spiked during the profile window",
            evidence: scheduled,
            recommendation: "Increase dispatcher throughput, lower dispatcher polling_interval, and inspect the dispatch query plan plus queue DB capacity."
          )
        ]
      end

      private

      def severity_for(scheduled)
        peak_overdue_delta = scheduled.fetch(:peak_overdue_count, 0).to_i - scheduled.fetch(:start_overdue_count, 0).to_i
        peak_lag_delta = scheduled.fetch(:peak_oldest_lag_seconds, 0).to_f - scheduled.fetch(:start_oldest_lag_seconds, 0).to_f

        return :high if peak_overdue_delta >= HIGH_OVERDUE_DELTA
        return :high if scheduled.fetch(:peak_overdue_count, 0).to_i >= HIGH_OVERDUE_DEPTH
        return :high if peak_lag_delta >= HIGH_LAG_GROWTH_SECONDS

        :medium
      end
    end
  end
end
