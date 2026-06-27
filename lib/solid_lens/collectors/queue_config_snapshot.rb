# frozen_string_literal: true

module SolidLens
  module Collectors
    class QueueConfigSnapshot
      RESERVED_POOL_CONNECTIONS = 2

      def initialize(mode:, workers:, dispatchers:, scheduler:, configured_processes:, worker_defaults:)
        @mode = mode
        @workers = workers
        @dispatchers = dispatchers
        @scheduler = scheduler
        @configured_processes = configured_processes
        @worker_defaults = worker_defaults
      end

      def to_h
        {
          mode: mode,
          workers: workers,
          dispatchers: dispatchers,
          scheduler: scheduler,
          configured_processes: configured_processes,
          worker_process_count: worker_process_count,
          dispatcher_count: dispatcher_count,
          scheduler_count: scheduler_count,
          worker_thread_capacity: worker_thread_capacity,
          max_worker_threads: max_worker_threads,
          required_pool_size: required_pool_size,
          wildcard_queue_specs: wildcard_queue_specs
        }
      end

      private

      attr_reader :configured_processes, :dispatchers, :mode, :scheduler, :worker_defaults, :workers

      def worker_process_count
        configured_processes.count { |process| process.fetch("kind") == "worker" }
      end

      def dispatcher_count
        configured_processes.count { |process| process.fetch("kind") == "dispatcher" }
      end

      def scheduler_count
        configured_processes.count { |process| process.fetch("kind") == "scheduler" }
      end

      def worker_thread_capacity
        configured_processes.sum do |process|
          next 0 unless process.fetch("kind") == "worker"

          process.fetch("attributes", {}).fetch("threads", worker_defaults.fetch("threads")).to_i
        end
      end

      def max_worker_threads
        workers.map { |worker| worker.fetch("threads", worker_defaults.fetch("threads")).to_i }.max || 0
      end

      def required_pool_size
        max_worker_threads.zero? ? 0 : max_worker_threads + RESERVED_POOL_CONNECTIONS
      end

      def wildcard_queue_specs
        workers.flat_map do |worker|
          queues = worker.fetch("queues", "*")
          Array(queues).filter_map do |queue|
            queue_name = queue.to_s
            queue_name if queue_name.include?("*")
          end
        end.uniq.sort
      end
    end
  end
end
