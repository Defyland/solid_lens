# frozen_string_literal: true

module SolidLens
  module Collectors
    class TableExplainCollector
      def initialize(connection:, queue_config:, database:)
        @connection = connection
        @queue_config = queue_config
        @database = database
      end

      def collect(existing:, paused:, table_counts:)
        explain_queries(existing, paused, table_counts).each_with_object({}) do |(name, definition), result|
          result[name] = definition.merge(rows: rows(definition.fetch(:explain_sql)))
        rescue => error
          result[name] = definition.merge(error: "#{error.class}: #{error.message}")
        end
      end

      private

      attr_reader :connection, :database, :queue_config

      def explain_queries(existing, paused, table_counts)
        queries = {}

        if existing.include?("solid_queue_ready_executions")
          queries[:poll_all] = explain_query(
            sql: "SELECT job_id FROM solid_queue_ready_executions ORDER BY priority ASC, job_id ASC LIMIT 1#{locking_clause}",
            table: "solid_queue_ready_executions",
            expected_indexes: ["index_solid_queue_poll_all"]
          )

          if (queue_name = preferred_queue_name)
            queries[:poll_by_queue] = explain_query(
              sql: "SELECT job_id FROM solid_queue_ready_executions WHERE queue_name = #{connection.quote(queue_name)} ORDER BY priority ASC, job_id ASC LIMIT 1#{locking_clause}",
              table: "solid_queue_ready_executions",
              expected_indexes: ["index_solid_queue_poll_by_queue"]
            )
          end

          if (wildcard_sql = wildcard_discovery_sql)
            queries[:discover_wildcard_queues] = explain_query(
              sql: wildcard_sql,
              table: "solid_queue_ready_executions",
              expected_indexes: ["index_solid_queue_poll_by_queue"]
            )
          elsif paused.any?
            queries[:discover_all_queues] = explain_query(
              sql: "SELECT DISTINCT(queue_name) FROM solid_queue_ready_executions",
              table: "solid_queue_ready_executions",
              expected_indexes: ["index_solid_queue_poll_by_queue"]
            )
          end
        end

        if existing.include?("solid_queue_scheduled_executions")
          queries[:dispatch_due] = explain_query(
            sql: "SELECT job_id FROM solid_queue_scheduled_executions WHERE scheduled_at <= CURRENT_TIMESTAMP ORDER BY scheduled_at ASC, priority ASC, job_id ASC LIMIT 1#{locking_clause}",
            table: "solid_queue_scheduled_executions",
            expected_indexes: ["index_solid_queue_dispatch_all"]
          )
        end

        if existing.include?("solid_queue_blocked_executions") && table_counts.fetch("solid_queue_blocked_executions", 0).positive?
          queries[:release_blocked] = explain_query(
            sql: "SELECT job_id FROM solid_queue_blocked_executions WHERE concurrency_key = #{connection.quote(sample_blocked_concurrency_key)} ORDER BY priority ASC, job_id ASC LIMIT 1#{locking_clause}",
            table: "solid_queue_blocked_executions",
            expected_indexes: ["index_solid_queue_blocked_executions_for_release"]
          )
        end

        queries
      end

      def explain_query(sql:, table:, expected_indexes:)
        {
          sql: sql,
          explain_sql: "#{explain_prefix} #{sql}",
          adapter: adapter_name,
          table: table,
          expected_indexes: expected_indexes
        }
      end

      def explain_prefix
        return "EXPLAIN QUERY PLAN" if adapter_name.include?("sqlite")
        return "EXPLAIN (FORMAT JSON)" if adapter_name.include?("postgres")

        "EXPLAIN"
      end

      def locking_clause
        return "" if adapter_name.include?("sqlite")
        return " FOR UPDATE SKIP LOCKED" if database[:skip_locked_supported]

        " FOR UPDATE"
      end

      def preferred_queue_name
        workers = Array(queue_config[:workers])
        queues = workers.flat_map { |worker| Array(worker["queues"]) }.map(&:to_s)
        queues.find { |queue| !queue.include?("*") } || first_existing_queue_name
      end

      def wildcard_discovery_sql
        specs = Array(queue_config[:wildcard_queue_specs]).map(&:to_s).reject { |queue| queue == "*" }
        return if specs.empty?

        conditions = specs.map do |spec|
          "queue_name LIKE #{connection.quote(spec.tr("*", "%"))}"
        end.join(" OR ")

        "SELECT DISTINCT(queue_name) FROM solid_queue_ready_executions WHERE #{conditions}"
      end

      def adapter_name
        database[:adapter_name].to_s.downcase.presence || connection.adapter_name.to_s.downcase
      end

      def first_existing_queue_name
        connection.select_value("SELECT queue_name FROM solid_queue_ready_executions ORDER BY queue_name ASC LIMIT 1")
      rescue
        nil
      end

      def sample_blocked_concurrency_key
        connection.select_value("SELECT concurrency_key FROM solid_queue_blocked_executions ORDER BY concurrency_key ASC LIMIT 1")
      rescue
        nil
      end

      def rows(sql)
        connection.select_all(sql).to_a.map { |row| row.stringify_keys }
      end
    end
  end
end
