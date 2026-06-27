# frozen_string_literal: true

require "erb"
require "yaml"
require_relative "queue_config_file_reader"
require_relative "queue_config_snapshot"
require_relative "queue_config_runtime_reader"
require_relative "queue_config_value_support"

module SolidLens
  module Collectors
    class QueueConfigCollector
      include QueueConfigValueSupport

      def initialize(path: nil, env: nil)
        @path = path
        @env = env
      end

      def collect
        @runtime_configuration_error = nil
        config = load_config
        snapshot = collect_snapshot(config.fetch(:data, {}))

        {
          path: config[:path],
          file_found: config[:file_found],
          file_error: config[:file_error],
          runtime_error: @runtime_configuration_error,
          error: combined_error(config[:error], @runtime_configuration_error),
          environment: env
        }.merge(snapshot.to_h)
      end

      private

      attr_reader :path

      def collect_snapshot(data)
        runtime_config = runtime_configuration
        return snapshot_from(runtime_reader(runtime_config).read) if runtime_config

        snapshot_from(file_reader(data).read)
      rescue => error
        @runtime_configuration_error = combined_error(@runtime_configuration_error, "#{error.class}: #{error.message}")
        snapshot_from(file_reader(data).read)
      end

      def load_config
        resolved_path = path || ENV["SOLID_QUEUE_CONFIG"] || default_path
        return {path: resolved_path, file_found: false, data: {}} unless resolved_path && File.exist?(resolved_path)

        raw = ERB.new(File.read(resolved_path)).result
        data = YAML.safe_load(raw, permitted_classes: [Symbol], aliases: true) || {}
        {path: resolved_path, file_found: true, data: stringify_keys(data)}
      rescue => error
        {
          path: resolved_path,
          file_found: File.exist?(resolved_path.to_s),
          data: {},
          file_error: "#{error.class}: #{error.message}",
          error: "#{error.class}: #{error.message}"
        }
      end

      def build_snapshot(workers:, dispatchers:, scheduler:, configured_processes:, mode:)
        QueueConfigSnapshot.new(
          mode: mode,
          workers: workers,
          dispatchers: dispatchers,
          scheduler: scheduler,
          configured_processes: configured_processes,
          worker_defaults: worker_defaults
        )
      end

      def runtime_configuration
        return unless defined?(SolidQueue::Configuration)

        SolidQueue::Configuration.new
      rescue => error
        @runtime_configuration_error = "#{error.class}: #{error.message}"
        nil
      end

      def combined_error(*values)
        errors = values.compact.reject(&:empty?)
        errors.empty? ? nil : errors.join("; ")
      end

      def runtime_reader(configuration)
        QueueConfigRuntimeReader.new(
          configuration: configuration,
          worker_defaults: worker_defaults,
          dispatcher_defaults: dispatcher_defaults,
          scheduler_defaults: scheduler_defaults
        )
      end

      def file_reader(data)
        QueueConfigFileReader.new(
          data: data,
          env: env,
          worker_defaults: worker_defaults,
          dispatcher_defaults: dispatcher_defaults,
          scheduler_defaults: scheduler_defaults
        )
      end

      def snapshot_from(payload)
        build_snapshot(**payload)
      end

      def worker_defaults
        defaults = defined?(SolidQueue::Configuration::WORKER_DEFAULTS) ? SolidQueue::Configuration::WORKER_DEFAULTS : {
          queues: "*",
          threads: 3,
          processes: 1,
          polling_interval: 0.1
        }

        stringify_keys(defaults)
      end

      def dispatcher_defaults
        defaults = defined?(SolidQueue::Configuration::DISPATCHER_DEFAULTS) ? SolidQueue::Configuration::DISPATCHER_DEFAULTS : {
          batch_size: 500,
          polling_interval: 1,
          concurrency_maintenance: true,
          concurrency_maintenance_interval: 600
        }

        stringify_keys(defaults)
      end

      def scheduler_defaults
        defaults = defined?(SolidQueue::Configuration::SCHEDULER_DEFAULTS) ? SolidQueue::Configuration::SCHEDULER_DEFAULTS : {
          polling_interval: 5,
          dynamic_tasks_enabled: false
        }

        stringify_keys(defaults)
      end

      def default_path
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.join("config/queue.yml").to_s
        end
      end

      def env
        @env ||= if defined?(Rails) && Rails.respond_to?(:env)
          Rails.env.to_s
        else
          ENV.fetch("RAILS_ENV", "production")
        end
      end
    end
  end
end
