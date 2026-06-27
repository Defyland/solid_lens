# frozen_string_literal: true

require "json"

module SolidLens
  module Analyzers
    class ExplainPlanAnalyzer
      def initialize(explains)
        @explains = explains
      end

      def risky_queries
        explains.each_with_object({}) do |(name, payload), result|
          analysis = analyze(payload)
          next unless analysis[:risky]

          result[name] = payload.merge(analysis: analysis)
        end
      end

      private

      attr_reader :explains

      def analyze(payload)
        return {risky: true, reasons: ["explain_error"]} if payload[:error]

        adapter = payload.fetch(:adapter, "").downcase

        if adapter.include?("sqlite")
          analyze_sqlite(payload)
        elsif adapter.include?("postgres")
          analyze_postgres(payload)
        else
          analyze_mysql_like(payload)
        end
      end

      def analyze_sqlite(payload)
        details = payload.fetch(:rows, []).map { |row| row.fetch("detail", "").to_s }
        reasons = []
        reasons << "full_scan" if details.any? { |detail| detail.match?(/\bSCAN\b/i) && !detail.match?(/\bUSING (?:COVERING )?INDEX\b/i) }
        reasons << "temp_btree" if details.any? { |detail| detail.match?(/USE TEMP B-TREE/i) }

        {risky: reasons.any?, reasons: reasons, details: details}
      end

      def analyze_mysql_like(payload)
        rows = payload.fetch(:rows, [])
        reasons = []

        reasons << "full_table_scan" if rows.any? { |row| row.fetch("type", "").to_s.casecmp("ALL").zero? }
        reasons << "filesort" if rows.any? { |row| row.fetch("Extra", "").to_s.match?(/Using filesort/i) }
        reasons << "using_temporary" if rows.any? { |row| row.fetch("Extra", "").to_s.match?(/Using temporary/i) }
        reasons << "expected_index_missing" if expected_index_missing?(payload)

        {
          risky: reasons.any?,
          reasons: reasons,
          keys: rows.map { |row| row["key"] }.compact
        }
      end

      def analyze_postgres(payload)
        nodes = postgres_nodes(payload)
        node_types = nodes.map { |node| node["Node Type"].to_s }
        reasons = []

        reasons << "seq_scan" if node_types.any? { |type| type.casecmp("Seq Scan").zero? }
        reasons << "sort_node" if node_types.any? { |type| type.casecmp("Sort").zero? }
        reasons << "expected_index_missing" if expected_index_missing?(payload)

        {
          risky: reasons.any?,
          reasons: reasons,
          node_types: node_types
        }
      end

      def expected_index_missing?(payload)
        expected = Array(payload[:expected_indexes]).map(&:to_s)
        return false if expected.empty?

        rows = payload.fetch(:rows, [])
        used_keys = rows.flat_map { |row| row.values }.map(&:to_s)
        postgres_nodes(payload).flat_map { |node| node.values }.each { |value| used_keys << value.to_s }

        expected.none? { |index| used_keys.any? { |value| value.include?(index) } }
      end

      def postgres_nodes(payload)
        rows = payload.fetch(:rows, [])
        raw = rows.first&.values&.first
        parsed = case raw
        when String
          JSON.parse(raw)
        when Array
          raw
        else
          []
        end

        root = parsed.first.is_a?(Hash) ? parsed.first["Plan"] : nil
        flatten_postgres_nodes(root)
      rescue JSON::ParserError
        []
      end

      def flatten_postgres_nodes(node)
        return [] unless node.is_a?(Hash)

        [node] + Array(node["Plans"]).flat_map { |child| flatten_postgres_nodes(child) }
      end
    end
  end
end
