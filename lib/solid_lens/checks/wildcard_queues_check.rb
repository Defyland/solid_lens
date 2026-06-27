# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class WildcardQueuesCheck < BaseCheck
      def call
        specs = queue_config.fetch(:wildcard_queue_specs, [])
        return [] if specs.empty?

        ready_count = tables.fetch(:counts, {}).fetch("solid_queue_ready_executions", 0).to_i
        severity = (ready_count > 10_000) ? :high : :medium

        [
          finding(
            id: "solid_queue.queues.wildcard",
            severity: severity,
            title: "Workers use wildcard queue matching",
            evidence: {wildcard_queue_specs: specs, ready_executions: ready_count},
            recommendation: "Prefer explicit queue names for hot paths. Prefix wildcards force Solid Queue to discover matching queues and can make polling dependent on ready table size."
          )
        ]
      end
    end
  end
end
