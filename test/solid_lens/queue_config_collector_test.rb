# frozen_string_literal: true

require "tempfile"
require "test_helper"

class QueueConfigCollectorTest < Minitest::Test
  WORKER_DEFAULTS = {
    "queues" => "*",
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

  SCHEDULER_DEFAULTS = {
    "polling_interval" => 5,
    "dynamic_tasks_enabled" => false
  }.freeze

  FakeProcess = Struct.new(:kind, :attributes)
  FakeRuntimeConfiguration = Struct.new(
    :workers_options,
    :dispatchers_options,
    :scheduler_options,
    :configured_processes,
    :mode
  )
  FakeBrokenRuntimeConfiguration = Class.new do
    def workers_options
      raise "failed to read workers options"
    end
  end

  def test_collect_resolves_file_defaults_and_derived_topology_metrics
    path = write_queue_config(<<~YAML)
      staging:
        workers:
          - queues:
              - critical*
            threads: 4
        dispatchers:
          - polling_interval: 10
        scheduler:
          dynamic_tasks_enabled: true
    YAML

    config = collector_with(path: path, env: "staging", runtime: nil).collect

    assert_equal path, config.fetch(:path)
    assert_equal true, config.fetch(:file_found)
    assert_nil config[:error]
    assert_nil config[:file_error]
    assert_nil config[:runtime_error]
    assert_equal "staging", config.fetch(:environment)
    assert_equal "unknown", config.fetch(:mode)
    assert_equal(
      [{"queues" => ["critical*"], "threads" => 4, "processes" => 1, "polling_interval" => 0.1}],
      config.fetch(:workers)
    )
    assert_equal(
      [{
        "batch_size" => 500,
        "polling_interval" => 10,
        "concurrency_maintenance" => true,
        "concurrency_maintenance_interval" => 600
      }],
      config.fetch(:dispatchers)
    )
    assert_equal({"polling_interval" => 5, "dynamic_tasks_enabled" => true}, config.fetch(:scheduler))
    assert_equal 1, config.fetch(:worker_process_count)
    assert_equal 1, config.fetch(:dispatcher_count)
    assert_equal 1, config.fetch(:scheduler_count)
    assert_equal 4, config.fetch(:worker_thread_capacity)
    assert_equal 4, config.fetch(:max_worker_threads)
    assert_equal 6, config.fetch(:required_pool_size)
    assert_equal ["critical*"], config.fetch(:wildcard_queue_specs)
  end

  def test_collect_prefers_runtime_configuration_over_file_data
    path = write_queue_config(<<~YAML)
      production:
        workers:
          - queues:
              - file
            threads: 2
            processes: 1
    YAML

    runtime = FakeRuntimeConfiguration.new(
      [{"queues" => ["runtime"], "threads" => 8}],
      [{"batch_size" => 250}],
      {"dynamic_tasks_enabled" => false},
      [
        FakeProcess.new("dispatcher", {"batch_size" => 250, "polling_interval" => 1}),
        FakeProcess.new("worker", {"queues" => ["runtime"], "threads" => 8}),
        FakeProcess.new("worker", {"queues" => ["runtime"], "threads" => 8}),
        FakeProcess.new("scheduler", {"dynamic_tasks_enabled" => false})
      ],
      :fork
    )

    config = collector_with(path: path, env: "production", runtime: runtime).collect

    assert_equal "fork", config.fetch(:mode)
    assert_nil config[:file_error]
    assert_nil config[:runtime_error]
    assert_equal(
      [{"queues" => ["runtime"], "threads" => 8, "processes" => 1, "polling_interval" => 0.1}],
      config.fetch(:workers)
    )
    assert_equal(
      [{
        "batch_size" => 250,
        "polling_interval" => 1,
        "concurrency_maintenance" => true,
        "concurrency_maintenance_interval" => 600
      }],
      config.fetch(:dispatchers)
    )
    assert_equal({"polling_interval" => 5, "dynamic_tasks_enabled" => false}, config.fetch(:scheduler))
    assert_equal 2, config.fetch(:worker_process_count)
    assert_equal 16, config.fetch(:worker_thread_capacity)
    assert_equal 8, config.fetch(:max_worker_threads)
    assert_equal 10, config.fetch(:required_pool_size)
    assert_empty config.fetch(:wildcard_queue_specs)
    assert_equal({
      "batch_size" => 250,
      "polling_interval" => 1,
      "concurrency_maintenance" => true,
      "concurrency_maintenance_interval" => 600
    }, config.fetch(:configured_processes).first.fetch("attributes"))
    assert_equal({
      "queues" => ["runtime"],
      "threads" => 8,
      "processes" => 1,
      "polling_interval" => 0.1
    }, config.fetch(:configured_processes)[1].fetch("attributes"))
    assert_equal({
      "polling_interval" => 5,
      "dynamic_tasks_enabled" => false
    }, config.fetch(:configured_processes).last.fetch("attributes"))
  end

  def test_collect_falls_back_to_file_data_when_runtime_configuration_errors
    path = write_queue_config(<<~YAML)
      production:
        workers:
          - queues:
              - mailers*
            threads: 5
            processes: 2
    YAML

    config = collector_with(path: path, env: "production", runtime_error: "RuntimeError: failed to build runtime config").collect

    assert_equal "unknown", config.fetch(:mode)
    assert_equal 2, config.fetch(:worker_process_count)
    assert_equal ["mailers*"], config.fetch(:wildcard_queue_specs)
    assert_includes config.fetch(:error), "RuntimeError: failed to build runtime config"
    assert_nil config[:file_error]
    assert_equal "RuntimeError: failed to build runtime config", config.fetch(:runtime_error)
  end

  def test_collect_returns_sorted_unique_wildcard_queue_specs
    path = write_queue_config(<<~YAML)
      production:
        workers:
          - queues:
              - zeta*
              - alpha*
          - queues:
              - alpha*
              - default
    YAML

    config = collector_with(path: path, env: "production", runtime: nil).collect

    assert_equal ["alpha*", "zeta*"], config.fetch(:wildcard_queue_specs)
  end

  def test_collect_exposes_file_error_separately_from_runtime_error
    path = write_queue_config(<<~YAML)
      production:
        workers: [
    YAML

    config = collector_with(path: path, env: "production", runtime: nil).collect

    assert_includes config.fetch(:error), "Psych::SyntaxError"
    assert_match(/Psych::SyntaxError/, config.fetch(:file_error))
    assert_nil config[:runtime_error]
  end

  def test_collect_falls_back_to_file_data_when_runtime_access_raises
    path = write_queue_config(<<~YAML)
      production:
        workers:
          - queues:
              - mailers*
            threads: 5
            processes: 2
    YAML

    config = collector_with(path: path, env: "production", runtime: FakeBrokenRuntimeConfiguration.new).collect

    assert_equal "unknown", config.fetch(:mode)
    assert_equal 2, config.fetch(:worker_process_count)
    assert_equal ["mailers*"], config.fetch(:wildcard_queue_specs)
    assert_match(/RuntimeError: failed to read workers options/, config.fetch(:runtime_error))
  end

  private

  def collector_with(path:, env:, runtime: nil, runtime_error: nil)
    collector = SolidLens::Collectors::QueueConfigCollector.new(path: path, env: env)
    collector.define_singleton_method(:worker_defaults) { WORKER_DEFAULTS }
    collector.define_singleton_method(:dispatcher_defaults) { DISPATCHER_DEFAULTS }
    collector.define_singleton_method(:scheduler_defaults) { SCHEDULER_DEFAULTS }

    if runtime_error
      collector.define_singleton_method(:runtime_configuration) do
        @runtime_configuration_error = runtime_error
        nil
      end
    else
      collector.define_singleton_method(:runtime_configuration) { runtime }
    end

    collector
  end

  def write_queue_config(contents)
    file = Tempfile.new(["queue", ".yml"])
    file.write(contents)
    file.flush
    file.path
  ensure
    file.close
  end
end
