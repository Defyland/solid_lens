# frozen_string_literal: true

require_relative "blocked_backlog_builder"
require_relative "ready_backlog_builder"
require_relative "recurring_task_health_builder"
require_relative "scheduled_backlog_builder"

module SolidLens
  module Collectors
    module ProfileEvidence
      class ExecutionStateBuilder
        def initialize(sample_set:)
          @sample_set = sample_set
        end

        def build
          {
            ready_backlog: ready_backlog_builder.build,
            scheduled_backlog: scheduled_backlog_builder.build,
            recurring_task_health: recurring_task_health_builder.build,
            blocked_backlog: blocked_backlog_builder.build
          }
        end

        private

        attr_reader :sample_set

        def ready_backlog_builder
          @ready_backlog_builder ||= ReadyBacklogBuilder.new(sample_set: sample_set)
        end

        def scheduled_backlog_builder
          @scheduled_backlog_builder ||= ScheduledBacklogBuilder.new(sample_set: sample_set)
        end

        def recurring_task_health_builder
          @recurring_task_health_builder ||= RecurringTaskHealthBuilder.new(sample_set: sample_set)
        end

        def blocked_backlog_builder
          @blocked_backlog_builder ||= BlockedBacklogBuilder.new(sample_set: sample_set)
        end
      end
    end
  end
end
