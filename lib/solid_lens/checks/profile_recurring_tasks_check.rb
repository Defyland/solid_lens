# frozen_string_literal: true

require_relative "base_check"
require_relative "scheduler_support"

module SolidLens
  module Checks
    class ProfileRecurringTasksCheck < BaseCheck
      include SchedulerSupport

      HIGH_OVERDUE_DELTA = 3
      HIGH_OVERDUE_DEPTH = 5
      HIGH_LAG_GROWTH_SECONDS = 60

      def call
        recurring = profile.fetch(:recurring_task_health, {})
        peak_overdue_count = recurring.fetch(:peak_overdue_count, 0).to_i
        finish_overdue_count = recurring.fetch(:finish_overdue_count, 0).to_i
        overdue_count_delta = recurring.fetch(:overdue_count_delta, 0).to_i
        peak_oldest_lag = recurring.fetch(:peak_oldest_lag_seconds, 0).to_f
        finish_oldest_lag = recurring.fetch(:finish_oldest_lag_seconds, 0).to_f
        oldest_lag_delta = recurring.fetch(:oldest_lag_delta_seconds, 0).to_f

        return [] unless peak_overdue_count.positive?
        return [] unless overdue_count_delta.positive? || oldest_lag_delta.positive? || peak_overdue_count > finish_overdue_count || peak_oldest_lag > finish_oldest_lag

        [
          finding(
            id: "solid_queue.profile.recurring.overdue_growing",
            severity: severity_for(recurring),
            title: "Recurring task lag grew or spiked during the profile window",
            evidence: recurring_finding_evidence(recurring),
            recommendation: recommendation
          )
        ]
      end

      private

      def recurring_finding_evidence(recurring)
        evidence = recurring.merge(
          scheduler_count: queue_config.fetch(:scheduler_count, 0),
          scheduler: queue_config.fetch(:scheduler, {})
        )
        issues = scheduler_issues
        issues.empty? ? evidence : evidence.merge(scheduler_issues: issues)
      end

      def severity_for(recurring)
        peak_overdue_delta = recurring.fetch(:peak_overdue_count, 0).to_i - recurring.fetch(:start_overdue_count, 0).to_i
        peak_lag_delta = recurring.fetch(:peak_oldest_lag_seconds, 0).to_f - recurring.fetch(:start_oldest_lag_seconds, 0).to_f

        return :high unless usable_scheduler?
        return :high if peak_overdue_delta >= HIGH_OVERDUE_DELTA
        return :high if recurring.fetch(:peak_overdue_count, 0).to_i >= HIGH_OVERDUE_DEPTH
        return :high if peak_lag_delta >= HIGH_LAG_GROWTH_SECONDS

        :medium
      end

      def recommendation
        if usable_scheduler?
          "Inspect scheduler throughput, recurring task schedules, and recent recurring enqueue activity before lag turns into missed recurring work."
        else
          "Run a scheduler with valid polling against this Solid Queue deployment or confirm another healthy deployment owns recurring work for this queue database."
        end
      end
    end
  end
end
