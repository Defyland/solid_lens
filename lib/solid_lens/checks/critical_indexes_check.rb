# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class CriticalIndexesCheck < BaseCheck
      REQUIRED_INDEXES = {
        "solid_queue_blocked_executions" => %w[index_solid_queue_blocked_executions_for_release index_solid_queue_blocked_executions_for_maintenance],
        "solid_queue_semaphores" => %w[index_solid_queue_semaphores_on_expires_at index_solid_queue_semaphores_on_key],
        "solid_queue_ready_executions" => %w[index_solid_queue_poll_all index_solid_queue_poll_by_queue],
        "solid_queue_scheduled_executions" => %w[index_solid_queue_dispatch_all],
        "solid_queue_processes" => %w[index_solid_queue_processes_on_last_heartbeat_at]
      }.freeze

      def call
        return [] unless tables[:available]

        missing = REQUIRED_INDEXES.each_with_object({}) do |(table, required), result|
          next unless tables.fetch(:existing_tables, []).include?(table)

          actual = tables.fetch(:indexes, {}).fetch(table, [])
          absent = required - actual
          result[table] = absent if absent.any?
        end

        return [] if missing.empty?

        [
          finding(
            id: "solid_queue.indexes.missing",
            severity: :high,
            title: "Critical Solid Queue indexes are missing",
            evidence: missing.transform_values do |absent|
              {
                missing_indexes: absent,
                existing_indexes: tables.fetch(:indexes, {})
              }
            end,
            recommendation: "Restore the missing Solid Queue indexes before trusting throughput or lag diagnostics. Missing poll, dispatch, blocked-recovery, or semaphore-cleanup indexes will distort both worker latency and EXPLAIN results."
          )
        ]
      end
    end
  end
end
