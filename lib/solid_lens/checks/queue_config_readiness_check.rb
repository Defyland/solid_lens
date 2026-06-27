# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class QueueConfigReadinessCheck < BaseCheck
      def call
        findings = []

        if queue_config[:file_error]
          findings << finding(
            id: "solid_queue.queue_config.file_unreadable",
            severity: :high,
            title: "Solid Queue queue.yml could not be read",
            evidence: file_evidence,
            recommendation: "Fix config/queue.yml syntax, ERB, or SOLID_QUEUE_CONFIG path so SolidLens can verify the intended queue topology."
          )
        end

        if queue_config[:runtime_error]
          findings << finding(
            id: "solid_queue.queue_config.runtime_unavailable",
            severity: queue_config[:file_error] ? :high : :medium,
            title: "Solid Queue runtime configuration could not be inspected",
            evidence: runtime_evidence,
            recommendation: "Ensure SolidQueue::Configuration can initialize in this environment, or keep config/queue.yml readable so SolidLens can fall back to file-based topology evidence."
          )
        end

        findings
      end

      private

      def file_evidence
        {
          path: queue_config[:path],
          file_found: queue_config[:file_found],
          environment: queue_config[:environment],
          file_error: queue_config[:file_error]
        }
      end

      def runtime_evidence
        {
          path: queue_config[:path],
          file_found: queue_config[:file_found],
          environment: queue_config[:environment],
          mode: queue_config[:mode],
          runtime_error: queue_config[:runtime_error]
        }
      end
    end
  end
end
