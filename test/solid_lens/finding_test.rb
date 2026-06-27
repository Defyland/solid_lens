# frozen_string_literal: true

require "test_helper"

class FindingTest < Minitest::Test
  def test_rejects_unknown_severity
    assert_raises(ArgumentError) do
      SolidLens::Finding.new(id: "x", severity: :bad, title: "Bad", recommendation: "Fix")
    end
  end

  def test_serializes_to_hash
    finding = SolidLens::Finding.new(
      id: "solid_queue.pool.undersized",
      severity: :high,
      title: "Queue database pool is undersized",
      evidence: {worker_threads: 10},
      recommendation: "Increase pool"
    )

    assert_equal :high, finding.to_h.fetch(:severity)
    assert_equal({worker_threads: 10}, finding.to_h.fetch(:evidence))
  end
end
