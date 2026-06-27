# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/queue_config_snapshot"

class QueueConfigSnapshotTest < Minitest::Test
  def test_to_h_derives_topology_metrics_and_deduplicates_wildcards
    snapshot = SolidLens::Collectors::QueueConfigSnapshot.new(
      mode: "fork",
      workers: [
        {"queues" => ["zeta*", "alpha*"], "threads" => 4, "processes" => 2, "polling_interval" => 0.1},
        {"queues" => ["alpha*", "default"], "threads" => 2, "processes" => 1, "polling_interval" => 0.2}
      ],
      dispatchers: [{"batch_size" => 250, "polling_interval" => 1}],
      scheduler: {"dynamic_tasks_enabled" => true},
      configured_processes: [
        {"kind" => "dispatcher", "attributes" => {"batch_size" => 250}},
        {"kind" => "worker", "attributes" => {"threads" => 4}},
        {"kind" => "worker", "attributes" => {"threads" => 4}},
        {"kind" => "worker", "attributes" => {"threads" => 2}},
        {"kind" => "scheduler", "attributes" => {"dynamic_tasks_enabled" => true}}
      ],
      worker_defaults: {"threads" => 3}
    )

    result = snapshot.to_h

    assert_equal 3, result.fetch(:worker_process_count)
    assert_equal 1, result.fetch(:dispatcher_count)
    assert_equal 1, result.fetch(:scheduler_count)
    assert_equal 10, result.fetch(:worker_thread_capacity)
    assert_equal 4, result.fetch(:max_worker_threads)
    assert_equal 6, result.fetch(:required_pool_size)
    assert_equal ["alpha*", "zeta*"], result.fetch(:wildcard_queue_specs)
  end
end
