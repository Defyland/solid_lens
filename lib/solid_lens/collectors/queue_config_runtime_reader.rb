# frozen_string_literal: true

require_relative "queue_config_value_support"

module SolidLens
  module Collectors
    class QueueConfigRuntimeReader
      include QueueConfigValueSupport

      def initialize(configuration:, worker_defaults:, dispatcher_defaults:, scheduler_defaults:)
        @configuration = configuration
        @worker_defaults = worker_defaults
        @dispatcher_defaults = dispatcher_defaults
        @scheduler_defaults = scheduler_defaults
      end

      def read
        {
          workers: normalize_list(configuration.send(:workers_options), worker_defaults),
          dispatchers: normalize_list(configuration.send(:dispatchers_options), dispatcher_defaults),
          scheduler: scheduler,
          configured_processes: configuration.configured_processes.map { |process| normalize_process(process) },
          mode: configuration.mode.to_s
        }
      end

      private

      attr_reader :configuration, :dispatcher_defaults, :scheduler_defaults, :worker_defaults

      def normalize_process(process)
        attributes = stringify_keys(process.attributes)

        {
          "kind" => process.kind.to_s,
          "attributes" => normalized_process_attributes(process.kind.to_s, attributes)
        }
      end

      def normalized_process_attributes(kind, attributes)
        case kind
        when "worker"
          merge_defaults(worker_defaults, attributes)
        when "dispatcher"
          merge_defaults(dispatcher_defaults, attributes)
        when "scheduler"
          merge_defaults(scheduler_defaults, attributes)
        else
          attributes
        end
      end

      def scheduler
        @scheduler ||= begin
          scheduler_options = stringify_keys(configuration.send(:scheduler_options) || {})
          scheduler_options.empty? ? {} : merge_defaults(scheduler_defaults, scheduler_options)
        end
      end
    end
  end
end
