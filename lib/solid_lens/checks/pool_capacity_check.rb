# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class PoolCapacityCheck < BaseCheck
      RESERVED_CONNECTIONS = 2

      def call
        pool = database[:connection_pool_size].to_i
        return [] if pool <= 0

        worker_threads = queue_config.fetch(:max_worker_threads, 0).to_i
        return [] if worker_threads.zero?

        safe_worker_threads = pool - RESERVED_CONNECTIONS
        required_pool_size = queue_config.fetch(:required_pool_size, worker_threads + RESERVED_CONNECTIONS).to_i
        return [] if pool >= required_pool_size

        [
          finding(
            id: "solid_queue.pool.undersized",
            severity: :high,
            title: "Queue database pool is undersized",
            evidence: {
              worker_threads: worker_threads,
              queue_db_pool: pool,
              reserved_connections: RESERVED_CONNECTIONS,
              safe_worker_threads: safe_worker_threads,
              required_pool_size: required_pool_size,
              worker_process_count: queue_config[:worker_process_count],
              mode: queue_config[:mode]
            },
            recommendation: "Increase the queue DB pool to >= #{required_pool_size} or reduce worker threads to <= #{safe_worker_threads}."
          )
        ]
      end
    end
  end
end
