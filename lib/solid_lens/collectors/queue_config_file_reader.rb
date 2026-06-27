# frozen_string_literal: true

require_relative "queue_config_value_support"

module SolidLens
  module Collectors
    class QueueConfigFileReader
      include QueueConfigValueSupport

      def initialize(data:, env:, worker_defaults:, dispatcher_defaults:, scheduler_defaults:)
        @data = data
        @env = env
        @worker_defaults = worker_defaults
        @dispatcher_defaults = dispatcher_defaults
        @scheduler_defaults = scheduler_defaults
      end

      def read
        {
          workers: workers,
          dispatchers: dispatchers,
          scheduler: scheduler,
          configured_processes: configured_processes,
          mode: "unknown"
        }
      end

      private

      attr_reader :data, :dispatcher_defaults, :env, :scheduler_defaults, :worker_defaults

      def workers
        @workers ||= normalize_list(section["workers"], worker_defaults)
      end

      def dispatchers
        @dispatchers ||= normalize_list(section["dispatchers"], dispatcher_defaults)
      end

      def scheduler
        @scheduler ||= begin
          scheduler_config = stringify_keys(section.fetch("scheduler", {}))
          scheduler_config.empty? ? {} : merge_defaults(scheduler_defaults, scheduler_config)
        end
      end

      def configured_processes
        dispatcher_processes + worker_processes + scheduler_processes
      end

      def dispatcher_processes
        dispatchers.map { |attributes| {"kind" => "dispatcher", "attributes" => stringify_keys(attributes)} }
      end

      def worker_processes
        workers.flat_map do |worker|
          [stringify_keys(worker)] * worker.fetch("processes", worker_defaults.fetch("processes")).to_i
        end.map { |attributes| {"kind" => "worker", "attributes" => attributes} }
      end

      def scheduler_processes
        scheduler.empty? ? [] : [{"kind" => "scheduler", "attributes" => scheduler}]
      end

      def section
        @section ||= begin
          candidate = data[env]
          candidate.is_a?(Hash) ? candidate : data
        end
      end
    end
  end
end
