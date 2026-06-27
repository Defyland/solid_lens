# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class PausedQueuesCheck < BaseCheck
      def call
        paused = tables.fetch(:paused_queues, [])
        return [] if paused.empty?

        [
          finding(
            id: "solid_queue.queues.paused",
            severity: :medium,
            title: "Solid Queue has paused queues",
            evidence: {paused_queues: paused},
            recommendation: "Unpause queues unless this is an active incident response. Remove queues from worker config instead of leaving long-lived pauses."
          )
        ]
      end
    end
  end
end
