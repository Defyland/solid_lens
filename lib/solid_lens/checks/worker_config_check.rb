# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class WorkerConfigCheck < BaseCheck
      WORKER_DEFAULTS = {
        "threads" => 3,
        "processes" => 1,
        "polling_interval" => 0.1
      }.freeze

      DISPATCHER_DEFAULTS = {
        "batch_size" => 500,
        "polling_interval" => 1,
        "concurrency_maintenance" => true,
        "concurrency_maintenance_interval" => 600
      }.freeze

      HIGH_POLLING_INTERVAL_SECONDS = 5.0

      def call
        findings = []
        workers = queue_config.fetch(:workers, [])
        dispatchers = queue_config.fetch(:dispatchers, [])
        usable_dispatchers = usable_dispatchers(dispatchers)

        if workers.empty?
          findings << finding(
            id: "solid_queue.workers.none",
            severity: :high,
            title: "No Solid Queue workers are configured",
            evidence: {workers: workers},
            recommendation: "Configure at least one worker in config/queue.yml for queues that should execute jobs."
          )
        end

        if usable_dispatchers.empty? && tables.fetch(:overdue_scheduled_count, 0).positive?
          findings << finding(
            id: "solid_queue.dispatchers.none_with_due_jobs",
            severity: :high,
            title: "Scheduled jobs are due but no usable dispatchers are configured",
            evidence: {
              dispatchers: dispatchers,
              configured_dispatcher_count: dispatchers.size,
              overdue_scheduled_count: tables[:overdue_scheduled_count]
            },
            recommendation: "Configure at least one dispatcher with valid polling and batch settings, or remove scheduled jobs from this Solid Queue deployment."
          )
        end

        if (invalid = invalid_workers(workers)).any?
          findings << finding(
            id: "solid_queue.workers.invalid",
            severity: :high,
            title: "Solid Queue workers have invalid concurrency settings",
            evidence: {mode: queue_config[:mode], workers: invalid},
            recommendation: "Set worker threads >= 1, worker polling_interval > 0, and worker processes >= 1 unless you are intentionally running async mode."
          )
        end

        if (invalid = invalid_dispatchers(dispatchers)).any?
          findings << finding(
            id: "solid_queue.dispatchers.invalid",
            severity: :high,
            title: "Solid Queue dispatchers have invalid settings",
            evidence: {dispatchers: invalid},
            recommendation: "Set dispatcher polling_interval > 0, batch_size >= 1, and concurrency_maintenance_interval > 0 whenever concurrency maintenance is enabled."
          )
        end

        if (ignored = ignored_async_processes(workers)).any?
          findings << finding(
            id: "solid_queue.workers.processes.ignored_async",
            severity: :medium,
            title: "Worker processes are ignored in async mode",
            evidence: {mode: queue_config[:mode], workers: ignored},
            recommendation: "Use fork mode when you need multi-process parallelism, or remove processes from config/queue.yml so the effective topology is explicit."
          )
        end

        slow_pollers(workers).each do |worker|
          findings << finding(
            id: "solid_queue.workers.polling_interval.high",
            severity: :medium,
            title: "Worker polling interval is high",
            evidence: worker,
            recommendation: "Lower worker polling_interval when queue latency matters, then verify database load with solid_lens:profile."
          )
        end

        if (slow_dispatchers = slow_dispatchers(dispatchers)).any?
          findings << finding(
            id: "solid_queue.dispatchers.polling_interval.high",
            severity: dispatcher_polling_severity,
            title: "Dispatcher polling interval is high",
            evidence: {
              dispatchers: slow_dispatchers,
              overdue_scheduled_count: tables.fetch(:overdue_scheduled_count, 0)
            },
            recommendation: "Lower dispatcher polling_interval when scheduled-job latency or unblock latency matters, then verify the dispatch query plan with solid_lens:explain."
          )
        end

        findings
      end

      private

      def slow_pollers(workers)
        workers.each_with_index.filter_map do |worker, index|
          next unless worker.fetch("polling_interval", WORKER_DEFAULTS.fetch("polling_interval")).to_f > HIGH_POLLING_INTERVAL_SECONDS

          worker.merge("worker_index" => index)
        end
      end

      def slow_dispatchers(dispatchers)
        dispatchers.each_with_index.filter_map do |dispatcher, index|
          next unless dispatcher.fetch("polling_interval", DISPATCHER_DEFAULTS.fetch("polling_interval")).to_f > HIGH_POLLING_INTERVAL_SECONDS

          dispatcher.merge("dispatcher_index" => index)
        end
      end

      def usable_dispatchers(dispatchers)
        dispatchers.reject do |dispatcher|
          invalid_dispatcher_issues(dispatcher).any?
        end
      end

      def invalid_workers(workers)
        workers.each_with_index.filter_map do |worker, index|
          issues = []
          threads = worker.fetch("threads", WORKER_DEFAULTS.fetch("threads")).to_i
          processes = worker.fetch("processes", WORKER_DEFAULTS.fetch("processes")).to_i
          polling_interval = worker.fetch("polling_interval", WORKER_DEFAULTS.fetch("polling_interval")).to_f

          issues << "threads_must_be_positive" if threads < 1
          issues << "polling_interval_must_be_positive" if polling_interval <= 0
          issues << "processes_must_be_positive" if validate_processes? && processes < 1

          next if issues.empty?

          {
            "worker_index" => index,
            "queues" => Array(worker["queues"]),
            "threads" => threads,
            "processes" => processes,
            "polling_interval" => polling_interval,
            "issues" => issues
          }
        end
      end

      def invalid_dispatchers(dispatchers)
        dispatchers.each_with_index.filter_map do |dispatcher, index|
          issues = invalid_dispatcher_issues(dispatcher)
          polling_interval = dispatcher.fetch("polling_interval", DISPATCHER_DEFAULTS.fetch("polling_interval")).to_f
          batch_size = dispatcher.fetch("batch_size", DISPATCHER_DEFAULTS.fetch("batch_size")).to_i
          concurrency_maintenance = dispatcher.fetch("concurrency_maintenance", DISPATCHER_DEFAULTS.fetch("concurrency_maintenance"))
          concurrency_maintenance_interval = dispatcher.fetch("concurrency_maintenance_interval", DISPATCHER_DEFAULTS.fetch("concurrency_maintenance_interval")).to_f

          next if issues.empty?

          dispatcher.merge(
            "dispatcher_index" => index,
            "polling_interval" => polling_interval,
            "batch_size" => batch_size,
            "concurrency_maintenance" => concurrency_maintenance,
            "concurrency_maintenance_interval" => concurrency_maintenance_interval,
            "issues" => issues
          )
        end
      end

      def invalid_dispatcher_issues(dispatcher)
        issues = []
        polling_interval = dispatcher.fetch("polling_interval", DISPATCHER_DEFAULTS.fetch("polling_interval")).to_f
        batch_size = dispatcher.fetch("batch_size", DISPATCHER_DEFAULTS.fetch("batch_size")).to_i
        concurrency_maintenance = dispatcher.fetch("concurrency_maintenance", DISPATCHER_DEFAULTS.fetch("concurrency_maintenance"))
        concurrency_maintenance_interval = dispatcher.fetch("concurrency_maintenance_interval", DISPATCHER_DEFAULTS.fetch("concurrency_maintenance_interval")).to_f

        issues << "polling_interval_must_be_positive" if polling_interval <= 0
        issues << "batch_size_must_be_positive" if batch_size < 1
        if concurrency_maintenance && concurrency_maintenance_interval <= 0
          issues << "concurrency_maintenance_interval_must_be_positive"
        end

        issues
      end

      def ignored_async_processes(workers)
        return [] unless async_mode?

        workers.each_with_index.filter_map do |worker, index|
          configured_processes = worker.fetch("processes", WORKER_DEFAULTS.fetch("processes")).to_i
          next unless configured_processes > 1

          {
            "worker_index" => index,
            "queues" => Array(worker["queues"]),
            "configured_processes" => configured_processes,
            "effective_processes" => 1
          }
        end
      end

      def dispatcher_polling_severity
        tables.fetch(:overdue_scheduled_count, 0).to_i.positive? ? :high : :medium
      end

      def validate_processes?
        !async_mode?
      end

      def async_mode?
        queue_config.fetch(:mode, "").to_s.casecmp("async").zero?
      end
    end
  end
end
