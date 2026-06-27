# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/profile_evidence/claimed_execution_health_builder"

class ProfileClaimedExecutionHealthBuilderTest < Minitest::Test
  def test_build_summarizes_claimed_execution_health_profile
    samples = [
      sample(offset_seconds: 0.0, claimed_dead_count: 0, process_alive_threshold_seconds: 30),
      sample(offset_seconds: 5.0, claimed_dead_count: 1, oldest_claimed_dead_lag_seconds: 60.0, process_alive_threshold_seconds: 30),
      sample(offset_seconds: 10.0, claimed_dead_count: 0, process_alive_threshold_seconds: 30)
    ]

    result = build(samples)

    assert_equal 30, result.fetch(:process_alive_threshold_seconds)
    assert_equal 1, result.fetch(:peak_dead_count)
    assert_equal 60.0, result.fetch(:peak_oldest_dead_lag_seconds)
    assert_equal 3, result.fetch(:timeline).size
  end

  private

  def build(samples)
    sample_set = SolidLens::Collectors::ProfileEvidence::SampleSet.new(samples: samples, duration: 10.0)

    SolidLens::Collectors::ProfileEvidence::ClaimedExecutionHealthBuilder.new(sample_set: sample_set).build
  end

  def sample(offset_seconds:, claimed_dead_count:, oldest_claimed_dead_lag_seconds: 0.0, process_alive_threshold_seconds: nil)
    {
      offset_seconds: offset_seconds,
      evidence: {
        tables: {
          claimed_by_dead_process_count: claimed_dead_count,
          oldest_claimed_dead_lag_seconds: oldest_claimed_dead_lag_seconds,
          process_alive_threshold_seconds: process_alive_threshold_seconds
        }
      }
    }
  end
end
