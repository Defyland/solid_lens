# frozen_string_literal: true

require "test_helper"

class ProductSpecTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  PRODUCT_SPEC_PATH = File.join(ROOT, "docs/specs/product-direction.md")

  def test_product_direction_spec_exists_and_names_core_non_goals
    assert File.exist?(PRODUCT_SPEC_PATH)

    spec = File.read(PRODUCT_SPEC_PATH)

    assert_includes spec, "# SolidLens Product Direction"
    assert_includes spec, "It is not a generic monitoring product and it is not a dashboard."
    assert_includes spec, "Solid Cache or Solid Cable diagnostics"
    assert_includes spec, "collector -> evidence -> check -> severity -> recommendation -> reporter"
  end

  def test_runner_public_surface_stays_small_and_explicit
    assert_equal %i[doctor explain profile], SolidLens::Runner.public_instance_methods(false).sort
  end

  def test_runner_check_lists_match_product_contract
    assert_equal [
      SolidLens::Checks::SolidQueueConfiguredCheck,
      SolidLens::Checks::QueueConfigReadinessCheck,
      SolidLens::Checks::DatabaseConnectionCheck,
      SolidLens::Checks::SchemaReadinessCheck,
      SolidLens::Checks::CriticalIndexesCheck,
      SolidLens::Checks::DatabaseSkipLockedCheck,
      SolidLens::Checks::WorkerConfigCheck,
      SolidLens::Checks::SchedulerConfigCheck,
      SolidLens::Checks::PoolCapacityCheck,
      SolidLens::Checks::WildcardQueuesCheck,
      SolidLens::Checks::PausedQueuesCheck,
      SolidLens::Checks::ScheduledJobsCheck,
      SolidLens::Checks::RecurringTasksCheck,
      SolidLens::Checks::SemaphoreHealthCheck,
      SolidLens::Checks::BlockedExecutionsCheck,
      SolidLens::Checks::ClaimedExecutionsCheck,
      SolidLens::Checks::TableBloatCheck
    ], SolidLens::Runner::DOCTOR_CHECKS

    assert_equal(
      SolidLens::Runner::DOCTOR_CHECKS + [SolidLens::Checks::ExplainCheck],
      SolidLens::Runner::EXPLAIN_CHECKS
    )

    assert_equal(
      SolidLens::Runner::DOCTOR_CHECKS + [
        SolidLens::Checks::ProfileReadyBacklogCheck,
        SolidLens::Checks::ProfileScheduledBacklogCheck,
        SolidLens::Checks::ProfileRecurringTasksCheck,
        SolidLens::Checks::ProfileBlockedBacklogCheck,
        SolidLens::Checks::ProfileSemaphoreHealthCheck,
        SolidLens::Checks::ProfileClaimedExecutionsCheck,
        SolidLens::Checks::ProfileTableBloatCheck
      ],
      SolidLens::Runner::PROFILE_CHECKS
    )
  end

  def test_gem_root_has_no_web_ui_surface
    refute Dir.exist?(File.join(ROOT, "app"))
    refute File.exist?(File.join(ROOT, "lib/solid_lens/engine.rb"))
  end
end
