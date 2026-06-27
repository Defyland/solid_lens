# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class ScheduledJobsCheck < BaseCheck
      def call
        overdue = tables.fetch(:overdue_scheduled_count, 0).to_i
        return [] if overdue.zero?

        [
          finding(
            id: "solid_queue.scheduled.overdue",
            severity: :high,
            title: "Scheduled jobs are overdue",
            evidence: {
              overdue_scheduled_count: overdue,
              overdue_scheduled_grace_seconds: tables.fetch(:overdue_scheduled_grace_seconds, nil)
            },
            recommendation: "Verify dispatchers are running, dispatcher polling_interval is sane, and the dispatch query uses index_solid_queue_dispatch_all."
          )
        ]
      end
    end
  end
end
