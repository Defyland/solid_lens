# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class SolidQueueConfiguredCheck < BaseCheck
      def call
        findings = []
        runtime = evidence.fetch(:runtime, {})

        unless runtime[:solid_queue_version]
          findings << finding(
            id: "solid_queue.runtime.missing",
            severity: :high,
            title: "Solid Queue is not loaded",
            evidence: runtime,
            recommendation: "Add and boot the solid_queue gem before running SolidLens diagnostics."
          )
        end

        adapter = runtime[:active_job_queue_adapter].to_s
        if !adapter.empty? && !adapter.downcase.include?("solidqueue")
          findings << finding(
            id: "solid_queue.active_job.adapter_mismatch",
            severity: :medium,
            title: "Active Job is not using Solid Queue",
            evidence: {active_job_queue_adapter: runtime[:active_job_queue_adapter]},
            recommendation: "Set config.active_job.queue_adapter = :solid_queue for environments where Solid Queue should process jobs."
          )
        end

        findings
      end
    end
  end
end
