# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/queue_config_runtime_reader"

class QueueConfigRuntimeReaderTest < Minitest::Test
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

  def test_read_normalizes_runtime_options_and_processes
    runtime = FakeRuntimeConfiguration.new(
      [{"queues" => [:critical], "threads" => 8}],
      [{"batch_size" => 250}],
      {dynamic_tasks_enabled: false},
      [
        FakeProcess.new("dispatcher", {batch_size: 250}),
        FakeProcess.new("worker", {queues: [:critical], threads: 8}),
        FakeProcess.new("worker", {queues: [:critical], threads: 8}),
        FakeProcess.new("scheduler", {dynamic_tasks_enabled: false})
      ],
      :fork
    )

    result = SolidLens::Collectors::QueueConfigRuntimeReader.new(
      configuration: runtime,
      worker_defaults: WORKER_DEFAULTS,
      dispatcher_defaults: DISPATCHER_DEFAULTS,
      scheduler_defaults: SCHEDULER_DEFAULTS
    ).read

    assert_equal "fork", result.fetch(:mode)
    assert_equal [{"queues" => [:critical], "threads" => 8, "processes" => 1, "polling_interval" => 0.1}], result.fetch(:workers)
    assert_equal [{
      "batch_size" => 250,
      "polling_interval" => 1,
      "concurrency_maintenance" => true,
      "concurrency_maintenance_interval" => 600
    }], result.fetch(:dispatchers)
    assert_equal({"polling_interval" => 5, "dynamic_tasks_enabled" => false}, result.fetch(:scheduler))
    assert_equal 4, result.fetch(:configured_processes).size
    assert_equal "dispatcher", result.fetch(:configured_processes).first.fetch("kind")
    assert_equal({
      "batch_size" => 250,
      "polling_interval" => 1,
      "concurrency_maintenance" => true,
      "concurrency_maintenance_interval" => 600
    }, result.fetch(:configured_processes).first.fetch("attributes"))
    assert_equal({
      "queues" => [:critical],
      "threads" => 8,
      "processes" => 1,
      "polling_interval" => 0.1
    }, result.fetch(:configured_processes)[1].fetch("attributes"))
    assert_equal({
      "polling_interval" => 5,
      "dynamic_tasks_enabled" => false
    }, result.fetch(:configured_processes).last.fetch("attributes"))
  end
end
