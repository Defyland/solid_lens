# frozen_string_literal: true

require_relative "../analyzers/explain_plan_analyzer"
require_relative "base_check"

module SolidLens
  module Checks
    class ExplainCheck < BaseCheck
      def call
        explains = tables.fetch(:explains, {})
        return [] if explains.empty?

        bad = Analyzers::ExplainPlanAnalyzer.new(explains).risky_queries
        return [] if bad.empty?

        [
          finding(
            id: "solid_queue.explain.bad_plan",
            severity: :high,
            title: "Critical Solid Queue query has a risky execution plan",
            evidence: bad,
            recommendation: "Verify Solid Queue indexes exist, refresh database statistics, and remove wildcard/paused queue patterns that force DISTINCT queue discovery."
          )
        ]
      end
    end
  end
end
