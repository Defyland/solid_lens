# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/queue_config_file_reader"

class QueueConfigFileReaderTest < Minitest::Test
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

  def test_read_uses_environment_section_and_builds_configured_processes
    result = SolidLens::Collectors::QueueConfigFileReader.new(
      data: {
        "staging" => {
          "workers" => [
            {"queues" => ["critical*"], "threads" => 4, "processes" => 2}
          ],
          "dispatchers" => [
            {"polling_interval" => 10}
          ],
          "scheduler" => {
            "dynamic_tasks_enabled" => true
          }
        }
      },
      env: "staging",
      worker_defaults: WORKER_DEFAULTS,
      dispatcher_defaults: DISPATCHER_DEFAULTS,
      scheduler_defaults: SCHEDULER_DEFAULTS
    ).read

    assert_equal "unknown", result.fetch(:mode)
    assert_equal [{"queues" => ["critical*"], "threads" => 4, "processes" => 2, "polling_interval" => 0.1}], result.fetch(:workers)
    assert_equal [{
      "batch_size" => 500,
      "polling_interval" => 10,
      "concurrency_maintenance" => true,
      "concurrency_maintenance_interval" => 600
    }], result.fetch(:dispatchers)
    assert_equal({"polling_interval" => 5, "dynamic_tasks_enabled" => true}, result.fetch(:scheduler))
    assert_equal %w[dispatcher worker worker scheduler], result.fetch(:configured_processes).map { |process| process.fetch("kind") }
    assert_equal({"queues" => ["critical*"], "threads" => 4, "processes" => 2, "polling_interval" => 0.1}, result.fetch(:configured_processes)[1].fetch("attributes"))
    assert_equal({"polling_interval" => 5, "dynamic_tasks_enabled" => true}, result.fetch(:configured_processes).last.fetch("attributes"))
  end

  def test_read_falls_back_to_top_level_data_when_environment_section_is_missing
    result = SolidLens::Collectors::QueueConfigFileReader.new(
      data: {
        "workers" => [
          {"queues" => ["default"], "threads" => 2}
        ]
      },
      env: "production",
      worker_defaults: WORKER_DEFAULTS,
      dispatcher_defaults: DISPATCHER_DEFAULTS,
      scheduler_defaults: SCHEDULER_DEFAULTS
    ).read

    assert_equal [{"queues" => ["default"], "threads" => 2, "processes" => 1, "polling_interval" => 0.1}], result.fetch(:workers)
  end
end
