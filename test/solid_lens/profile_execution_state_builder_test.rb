# frozen_string_literal: true

require "test_helper"

class ProfileExecutionStateBuilderTest < Minitest::Test
  def test_build_assembles_all_profile_sections
    sample_set = SolidLens::Collectors::ProfileEvidence::SampleSet.new(
      samples: [
        {
          offset_seconds: 0.0,
          evidence: {
            tables: {
              counts: {
                "solid_queue_ready_executions" => 0,
                "solid_queue_blocked_executions" => 0
              }
            }
          }
        }
      ],
      duration: 10.0
    )

    result = SolidLens::Collectors::ProfileEvidence::ExecutionStateBuilder.new(sample_set: sample_set).build

    assert_equal %i[blocked_backlog ready_backlog recurring_task_health scheduled_backlog], result.keys.sort
  end
end
