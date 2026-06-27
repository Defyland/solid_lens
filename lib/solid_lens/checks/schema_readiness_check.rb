# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class SchemaReadinessCheck < BaseCheck
      def call
        return unavailable_findings unless tables[:available]

        missing = tables.fetch(:missing_tables, [])
        return [] if missing.empty?

        severity = (missing.size == Collectors::TableCollector::SOLID_QUEUE_TABLES.size) ? :high : :medium

        [
          finding(
            id: "solid_queue.schema.incomplete",
            severity: severity,
            title: "Solid Queue schema is incomplete",
            evidence: {
              existing_tables: tables[:existing_tables],
              missing_tables: missing
            },
            recommendation: "Install or migrate the Solid Queue schema in the queue database and verify that SolidQueue::Record points to the same database you inspected."
          )
        ]
      end

      private

      def unavailable_findings
        return [] unless database[:connected]

        [
          finding(
            id: "solid_queue.schema.unavailable",
            severity: :high,
            title: "Solid Queue schema could not be inspected",
            evidence: {
              error: tables[:error]
            },
            recommendation: "Verify the queue database user can inspect schema metadata and that Solid Queue tables exist in the selected database."
          )
        ]
      end
    end
  end
end
