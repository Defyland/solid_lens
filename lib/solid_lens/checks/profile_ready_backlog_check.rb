# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class ProfileReadyBacklogCheck < BaseCheck
      HIGH_READY_DELTA = 100
      HIGH_READY_DEPTH = 500
      HIGH_READY_AGE_GROWTH_SECONDS = 30

      def call
        ready = profile.fetch(:ready_backlog, {})
        peak_count = ready.fetch(:peak_count, 0).to_i
        finish_count = ready.fetch(:finish_count, 0).to_i
        delta = ready.fetch(:delta, 0).to_i
        peak_oldest_age = ready.fetch(:peak_oldest_age_seconds, 0).to_f
        finish_oldest_age = ready.fetch(:finish_oldest_age_seconds, 0).to_f
        oldest_age_delta = ready.fetch(:oldest_age_delta_seconds, 0).to_f

        return [] unless peak_count.positive?
        return [] unless delta.positive? || oldest_age_delta.positive? || peak_count > finish_count || peak_oldest_age > finish_oldest_age

        [
          finding(
            id: "solid_queue.profile.ready_backlog.growing",
            severity: severity_for(ready),
            title: "Ready execution backlog grew or spiked during the profile window",
            evidence: ready,
            recommendation: "Add worker throughput, reduce queue fan-out, or inspect the poll query and queue DB pool. Focus first on the queues with the highest peak depth, not only the final delta."
          )
        ]
      end

      private

      def severity_for(ready)
        peak_delta = ready.fetch(:peak_count, 0).to_i - ready.fetch(:start_count, 0).to_i
        peak_oldest_age_delta = ready.fetch(:peak_oldest_age_seconds, 0).to_f - ready.fetch(:start_oldest_age_seconds, 0).to_f

        return :high if peak_delta >= HIGH_READY_DELTA
        return :high if ready.fetch(:peak_count, 0).to_i >= HIGH_READY_DEPTH
        return :high if peak_oldest_age_delta >= HIGH_READY_AGE_GROWTH_SECONDS

        :medium
      end
    end
  end
end
