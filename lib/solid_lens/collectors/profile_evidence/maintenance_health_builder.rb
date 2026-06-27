# frozen_string_literal: true

require_relative "bloat_health_builder"
require_relative "claimed_execution_health_builder"
require_relative "semaphore_health_builder"

module SolidLens
  module Collectors
    module ProfileEvidence
      class MaintenanceHealthBuilder
        def initialize(sample_set:)
          @sample_set = sample_set
        end

        def build
          {
            semaphore_health: semaphore_health_builder.build,
            claimed_execution_health: claimed_execution_health_builder.build,
            bloat_health: bloat_health_builder.build
          }
        end

        private

        attr_reader :sample_set

        def semaphore_health_builder
          @semaphore_health_builder ||= SemaphoreHealthBuilder.new(sample_set: sample_set)
        end

        def claimed_execution_health_builder
          @claimed_execution_health_builder ||= ClaimedExecutionHealthBuilder.new(sample_set: sample_set)
        end

        def bloat_health_builder
          @bloat_health_builder ||= BloatHealthBuilder.new(sample_set: sample_set)
        end
      end
    end
  end
end
