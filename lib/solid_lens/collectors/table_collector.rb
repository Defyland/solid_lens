# frozen_string_literal: true

require "time"
require_relative "table_backlog_collector"
require_relative "table_bloat_collector"
require_relative "table_explain_collector"
require_relative "table_maintenance_collector"
require_relative "table_recurring_tasks_collector"

module SolidLens
  module Collectors
    class TableCollector
      SOLID_QUEUE_TABLES = %w[
        solid_queue_blocked_executions
        solid_queue_claimed_executions
        solid_queue_failed_executions
        solid_queue_jobs
        solid_queue_pauses
        solid_queue_processes
        solid_queue_ready_executions
        solid_queue_recurring_executions
        solid_queue_recurring_tasks
        solid_queue_scheduled_executions
        solid_queue_semaphores
      ].freeze

      def initialize(connection:, queue_config: {}, database: {}, explain: false, now: Time.now.utc, scheduled_grace_seconds: 60, process_alive_threshold: default_process_alive_threshold)
        @connection = connection
        @queue_config = queue_config
        @database = database
        @explain = explain
        @now = now
        @scheduled_grace_seconds = scheduled_grace_seconds
        @process_alive_threshold = process_alive_threshold
      end

      def collect
        return {available: false, error: "ActiveRecord connection unavailable"} unless connection

        existing = SOLID_QUEUE_TABLES.select { |table| connection.table_exists?(table) }
        table_indexes = indexes(existing)
        table_counts = counts(existing)
        backlog = backlog_evidence(existing)
        maintenance = maintenance_evidence(existing)

        {
          available: true,
          existing_tables: existing,
          missing_tables: SOLID_QUEUE_TABLES - existing,
          indexes: table_indexes,
          counts: table_counts,
          bloat: bloat(existing),
          explains: explain ? explains(existing, backlog.fetch(:paused_queues), table_counts) : {}
        }.merge(backlog).merge(maintenance).merge(recurring_tasks(existing))
      rescue => error
        {available: false, error: "#{error.class}: #{error.message}"}
      end

      private

      attr_reader :connection, :queue_config, :database, :explain, :now, :scheduled_grace_seconds, :process_alive_threshold

      def counts(existing)
        existing.to_h { |table| [table, select_count(table)] }
      end

      def indexes(existing)
        existing.to_h do |table|
          [table, connection.indexes(table).map(&:name).sort]
        end
      end

      def backlog_evidence(existing)
        TableBacklogCollector.new(
          connection: connection,
          now: now,
          scheduled_grace_seconds: scheduled_grace_seconds
        ).collect(existing: existing)
      end

      def maintenance_evidence(existing)
        TableMaintenanceCollector.new(
          connection: connection,
          now: now,
          process_alive_threshold: process_alive_threshold
        ).collect(existing: existing)
      end

      def bloat(existing)
        TableBloatCollector.new(connection: connection).collect(existing: existing)
      end

      def explains(existing, paused, table_counts)
        TableExplainCollector.new(
          connection: connection,
          queue_config: queue_config,
          database: database
        ).collect(existing: existing, paused: paused, table_counts: table_counts)
      end

      def recurring_tasks(existing)
        TableRecurringTasksCollector.new(connection: connection, now: now).collect(existing: existing)
      end

      def select_count(table, where = nil)
        sql = "SELECT COUNT(*) FROM #{table}"
        sql << " WHERE #{where}" if where
        connection.select_value(sql).to_i
      end

      def default_process_alive_threshold
        if defined?(SolidQueue) && SolidQueue.respond_to?(:process_alive_threshold)
          SolidQueue.process_alive_threshold
        else
          300
        end
      end
    end
  end
end
