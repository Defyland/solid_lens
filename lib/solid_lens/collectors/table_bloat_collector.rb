# frozen_string_literal: true

module SolidLens
  module Collectors
    class TableBloatCollector
      def initialize(connection:)
        @connection = connection
      end

      def collect(existing:)
        return {} unless postgres?

        table_list = existing.map { |table| connection.quote(table) }.join(", ")
        return {} if table_list.empty?

        rows(<<~SQL).sort_by { |row| row.fetch("relname") }.to_h do |row|
          SELECT relname, n_live_tup, n_dead_tup
          FROM pg_stat_user_tables
          WHERE relname IN (#{table_list})
          ORDER BY relname ASC
        SQL
          live = row.fetch("n_live_tup").to_i
          dead = row.fetch("n_dead_tup").to_i
          ratio = dead.zero? ? 0.0 : dead.to_f / [live + dead, 1].max
          [row.fetch("relname"), {live_tuples: live, dead_tuples: dead, dead_tuple_ratio: ratio.round(4)}]
        end
      rescue => error
        {error: "#{error.class}: #{error.message}"}
      end

      private

      attr_reader :connection

      def postgres?
        connection.adapter_name.to_s.downcase.include?("postgres")
      end

      def rows(sql)
        connection.select_all(sql).to_a.map { |row| row.stringify_keys }
      end
    end
  end
end
