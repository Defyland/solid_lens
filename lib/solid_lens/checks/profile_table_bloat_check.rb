# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class ProfileTableBloatCheck < BaseCheck
      MIN_DEAD_TUPLES = 1_000
      MIN_DEAD_TUPLE_RATIO = 0.2
      HIGH_DEAD_TUPLES = 10_000
      HIGH_DEAD_TUPLE_DELTA = 5_000
      HIGH_DEAD_TUPLE_RATIO = 0.4
      HIGH_DEAD_TUPLE_RATIO_DELTA = 0.1

      def call
        bloat = profile.fetch(:bloat_health, {})
        tables = bloat.fetch(:tables, {})
        growing_tables = tables.each_with_object({}) do |(table_name, stats), result|
          result[table_name] = stats if significant_growth?(stats)
        end
        return [] if growing_tables.empty?

        [
          finding(
            id: "solid_queue.profile.tables.bloat.growing",
            severity: severity_for(growing_tables),
            title: "Solid Queue table bloat grew during the profile window",
            evidence: bloat.merge(tables: growing_tables),
            recommendation: "Tighten autovacuum on the queue database, review job-retention churn on the affected tables, and rerun EXPLAIN because growing dead tuples can distort Solid Queue poll and dispatch plans."
          )
        ]
      end

      private

      def significant_growth?(stats)
        peak_dead_tuples = stats.fetch(:peak_dead_tuples, 0).to_i
        finish_dead_tuples = stats.fetch(:finish_dead_tuples, 0).to_i
        peak_dead_ratio = stats.fetch(:peak_dead_tuple_ratio, 0.0).to_f
        finish_dead_ratio = stats.fetch(:finish_dead_tuple_ratio, 0.0).to_f
        dead_tuple_delta = stats.fetch(:dead_tuple_delta, 0).to_i
        dead_tuple_ratio_delta = stats.fetch(:dead_tuple_ratio_delta, 0.0).to_f

        return false unless peak_dead_tuples >= MIN_DEAD_TUPLES
        return false unless peak_dead_ratio >= MIN_DEAD_TUPLE_RATIO

        dead_tuple_delta.positive? || dead_tuple_ratio_delta.positive? ||
          peak_dead_tuples > finish_dead_tuples || peak_dead_ratio > finish_dead_ratio
      end

      def severity_for(growing_tables)
        return :high if growing_tables.any? do |_table_name, stats|
          stats.fetch(:peak_dead_tuples, 0).to_i >= HIGH_DEAD_TUPLES ||
            stats.fetch(:dead_tuple_delta, 0).to_i >= HIGH_DEAD_TUPLE_DELTA ||
            stats.fetch(:peak_dead_tuple_ratio, 0.0).to_f >= HIGH_DEAD_TUPLE_RATIO ||
            stats.fetch(:dead_tuple_ratio_delta, 0.0).to_f >= HIGH_DEAD_TUPLE_RATIO_DELTA
        end

        :medium
      end
    end
  end
end
