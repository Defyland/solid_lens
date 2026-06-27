# frozen_string_literal: true

require_relative "base_check"
require_relative "scheduler_support"

module SolidLens
  module Checks
    class RecurringTasksCheck < BaseCheck
      include SchedulerSupport

      def call
        overdue = tables.fetch(:overdue_recurring_task_count, 0).to_i
        return [] if overdue.zero?

        findings = [
          finding(
            id: "solid_queue.recurring.overdue",
            severity: :high,
            title: "Recurring tasks appear overdue",
            evidence: recurring_evidence,
            recommendation: "Ensure at least one Solid Queue scheduler is actively running against this queue database, then verify recurring task schedules and recent enqueue activity."
          )
        ]

        if !usable_scheduler?(require_dynamic_tasks: dynamic_tasks_required?)
          findings << finding(
            id: "solid_queue.scheduler.none_with_overdue_recurring_tasks",
            severity: :high,
            title: "Recurring tasks are overdue and no usable scheduler is configured here",
            evidence: scheduler_finding_evidence,
            recommendation: scheduler_recommendation
          )
        end

        findings
      end

      private

      def dynamic_tasks_required?
        tables.fetch(:overdue_dynamic_recurring_task_count, 0).to_i.positive?
      end

      def scheduler_finding_evidence
        evidence = recurring_evidence.merge(
          mode: queue_config[:mode],
          scheduler: queue_config.fetch(:scheduler, {})
        )
        issues = scheduler_delivery_issues
        issues.empty? ? evidence : evidence.merge(scheduler_issues: issues)
      end

      def scheduler_delivery_issues
        issues = scheduler_issues(require_dynamic_tasks: dynamic_tasks_required?).dup
        issues << "scheduler_process_missing" if queue_config.fetch(:scheduler_count, 0).to_i.zero?
        issues
      end

      def scheduler_recommendation
        if dynamic_tasks_required?
          "Run a scheduler with valid polling against this Solid Queue deployment and enable dynamic task loading, or ensure another healthy deployment owns recurring work for the same queue database."
        else
          "Run a scheduler with valid polling against this Solid Queue deployment, or ensure another healthy deployment owns recurring work for the same queue database."
        end
      end

      def recurring_evidence
        {
          recurring_task_count: tables.fetch(:recurring_task_count, 0),
          dynamic_recurring_task_count: tables.fetch(:dynamic_recurring_task_count, 0),
          overdue_recurring_task_count: tables.fetch(:overdue_recurring_task_count, 0),
          overdue_dynamic_recurring_task_count: tables.fetch(:overdue_dynamic_recurring_task_count, 0),
          overdue_static_recurring_task_count: tables.fetch(:overdue_static_recurring_task_count, 0),
          oldest_recurring_task_lag_seconds: tables.fetch(:oldest_recurring_task_lag_seconds, 0.0),
          overdue_recurring_task_keys: tables.fetch(:overdue_recurring_task_keys, []),
          overdue_recurring_tasks: tables.fetch(:overdue_recurring_tasks, []),
          scheduler_count: queue_config.fetch(:scheduler_count, 0)
        }
      end
    end
  end
end
