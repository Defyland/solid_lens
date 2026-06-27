# frozen_string_literal: true

require_relative "base_check"
require_relative "scheduler_support"

module SolidLens
  module Checks
    class SchedulerConfigCheck < BaseCheck
      include SchedulerSupport

      HIGH_POLLING_INTERVAL_SECONDS = 5.0

      def call
        return [] unless scheduler_declared?

        findings = []

        if (issues = scheduler_issues).any?
          findings << finding(
            id: "solid_queue.scheduler.invalid",
            severity: :high,
            title: "Solid Queue scheduler has invalid settings",
            evidence: scheduler_evidence.merge(scheduler_issues: issues),
            recommendation: "Set scheduler polling_interval > 0 whenever a scheduler is configured for this Solid Queue deployment."
          )
        end

        if dynamic_tasks_disabled_finding?
          findings << finding(
            id: "solid_queue.scheduler.dynamic_tasks.disabled",
            severity: dynamic_tasks_disabled_severity,
            title: "Scheduler dynamic task loading is disabled",
            evidence: scheduler_evidence.merge(
              recurring_task_count: tables.fetch(:recurring_task_count, 0),
              dynamic_recurring_task_count: tables.fetch(:dynamic_recurring_task_count, 0),
              overdue_recurring_task_count: tables.fetch(:overdue_recurring_task_count, 0),
              overdue_recurring_task_keys: tables.fetch(:overdue_recurring_task_keys, [])
            ),
            recommendation: "Enable scheduler dynamic_tasks_enabled when this deployment should load database-backed recurring tasks, or confirm another healthy deployment owns dynamic recurring work for the same queue database."
          )
        end

        if scheduler_process_configured? && scheduler_polling_interval > HIGH_POLLING_INTERVAL_SECONDS
          findings << finding(
            id: "solid_queue.scheduler.polling_interval.high",
            severity: scheduler_polling_severity,
            title: "Scheduler polling interval is high",
            evidence: scheduler_evidence.merge(
              overdue_recurring_task_count: tables.fetch(:overdue_recurring_task_count, 0),
              oldest_recurring_task_lag_seconds: tables.fetch(:oldest_recurring_task_lag_seconds, 0.0)
            ),
            recommendation: "Lower scheduler polling_interval when recurring-task latency matters, then verify recurring lag with solid_lens:profile."
          )
        end

        findings
      end

      private

      def scheduler_declared?
        scheduler_process_configured? || !scheduler.empty?
      end

      def scheduler_process_configured?
        queue_config.fetch(:scheduler_count, 0).to_i.positive?
      end

      def scheduler_polling_severity
        tables.fetch(:overdue_recurring_task_count, 0).to_i.positive? ? :high : :medium
      end

      def dynamic_tasks_disabled_finding?
        scheduler_polling_interval.positive? &&
          !dynamic_tasks_enabled? &&
          tables.fetch(:dynamic_recurring_task_count, 0).to_i.positive?
      end

      def dynamic_tasks_disabled_severity
        tables.fetch(:overdue_recurring_task_count, 0).to_i.positive? ? :high : :medium
      end

      def scheduler_evidence
        {
          mode: queue_config[:mode],
          scheduler_count: queue_config.fetch(:scheduler_count, 0),
          scheduler: scheduler
        }
      end
    end
  end
end
