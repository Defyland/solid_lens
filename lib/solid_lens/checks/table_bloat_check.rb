# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class TableBloatCheck < BaseCheck
      def call
        bloat = tables.fetch(:bloat, {})
        return [] if bloat.empty? || bloat[:error]

        bloated = bloat.select do |_table, stats|
          stats.fetch(:dead_tuples, 0).to_i > 1_000 && stats.fetch(:dead_tuple_ratio, 0.0).to_f > 0.2
        end
        return [] if bloated.empty?

        [
          finding(
            id: "solid_queue.tables.bloat",
            severity: :medium,
            title: "Solid Queue tables show dead tuple bloat",
            evidence: bloated,
            recommendation: "Review autovacuum settings and job retention. Run VACUUM during a maintenance window if bloat is already affecting plans."
          )
        ]
      end
    end
  end
end
