# frozen_string_literal: true

module SolidLens
  module Checks
    module SchedulerSupport
      SCHEDULER_DEFAULTS = {
        "polling_interval" => 5,
        "dynamic_tasks_enabled" => false
      }.freeze

      private

      def scheduler
        queue_config.fetch(:scheduler, {})
      end

      def usable_scheduler?(require_dynamic_tasks: false)
        queue_config.fetch(:scheduler_count, 0).to_i.positive? &&
          scheduler_issues(require_dynamic_tasks: require_dynamic_tasks).empty?
      end

      def scheduler_issues(require_dynamic_tasks: false)
        return [] if queue_config.fetch(:scheduler_count, 0).to_i.zero? && scheduler.empty?

        issues = []
        issues << "polling_interval_must_be_positive" if scheduler_polling_interval <= 0
        issues << "dynamic_tasks_disabled" if require_dynamic_tasks && !dynamic_tasks_enabled?
        issues
      end

      def scheduler_polling_interval
        scheduler.fetch("polling_interval", SCHEDULER_DEFAULTS.fetch("polling_interval")).to_f
      end

      def dynamic_tasks_enabled?
        value = scheduler.fetch("dynamic_tasks_enabled", SCHEDULER_DEFAULTS.fetch("dynamic_tasks_enabled"))

        case value
        when true, 1 then true
        when false, 0 then false
        else value.to_s.casecmp("true").zero?
        end
      end
    end
  end
end
