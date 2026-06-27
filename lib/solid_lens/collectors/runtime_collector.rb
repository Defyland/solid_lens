# frozen_string_literal: true

module SolidLens
  module Collectors
    class RuntimeCollector
      def collect
        {
          ruby_version: RUBY_VERSION,
          rails_version: constant_version("Rails"),
          solid_queue_version: constant_version("SolidQueue") || gem_version("solid_queue"),
          active_job_queue_adapter: active_job_queue_adapter,
          rails_env: rails_env,
          solid_queue_process_heartbeat_interval_seconds: solid_queue_duration(:process_heartbeat_interval),
          solid_queue_process_alive_threshold_seconds: solid_queue_duration(:process_alive_threshold),
          solid_queue_connects_to: solid_queue_connects_to
        }
      end

      private

      def constant_version(name)
        mod = Object.const_get(name)
        return "unknown" unless mod.const_defined?(:VERSION)

        version = mod.const_get(:VERSION)
        if version.is_a?(Module) && version.const_defined?(:STRING)
          version.const_get(:STRING).to_s
        else
          version.to_s
        end
      rescue NameError
        nil
      end

      def gem_version(name)
        Gem::Specification.find_all_by_name(name).max_by(&:version)&.version&.to_s
      rescue
        nil
      end

      def active_job_queue_adapter
        return nil unless defined?(ActiveJob::Base)

        adapter = ActiveJob::Base.queue_adapter
        adapter.respond_to?(:class) ? adapter.class.name : adapter.to_s
      rescue => error
        "error: #{error.class}: #{error.message}"
      end

      def rails_env
        (defined?(Rails) && Rails.respond_to?(:env)) ? Rails.env.to_s : nil
      end

      def solid_queue_duration(name)
        return nil unless defined?(SolidQueue) && SolidQueue.respond_to?(name)

        SolidQueue.public_send(name).to_i
      rescue => error
        "error: #{error.class}: #{error.message}"
      end

      def solid_queue_connects_to
        return nil unless defined?(SolidQueue) && SolidQueue.respond_to?(:connects_to)

        SolidQueue.connects_to
      rescue => error
        "error: #{error.class}: #{error.message}"
      end
    end
  end
end
