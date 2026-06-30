# frozen_string_literal: true

require "test_helper"
require "solid_lens/package_audit"

class PackagingTest < Minitest::Test
  def test_built_gem_includes_public_contract_docs_and_excludes_package_audit_harness
    with_built_package do |gem_path|
      files = SolidLens::PackageAudit.package_contents(gem_path)

      SolidLens::PackageAudit::PUBLIC_DOCS.each do |path|
        assert_includes files, path
      end

      refute files.any? { |path| path.start_with?("lib/solid_lens/package_audit") }
    end
  end

  def test_gemspec_metadata_and_public_files_are_release_ready
    spec = Gem::Specification.load(File.join(project_root, "solid_lens.gemspec"))

    assert_equal SolidLens::VERSION, spec.version.to_s
    assert_equal "https://github.com/Defyland/solid_lens", spec.homepage
    assert_equal "https://rubygems.org", spec.metadata.fetch("allowed_push_host")
    assert_equal "#{spec.homepage}/issues", spec.metadata.fetch("bug_tracker_uri")
    assert_equal "#{spec.homepage}#readme", spec.metadata.fetch("documentation_uri")
    assert_includes spec.files, "docs/architecture.md"
    assert_includes spec.files, "docs/contract-versioning.md"
    assert_includes spec.files, "docs/decisions.md"
    assert_includes spec.files, "docs/specs/product-direction.md"
  end

  def test_built_public_docs_do_not_embed_absolute_local_paths
    with_built_package do |gem_path|
      SolidLens::PackageAudit.packaged_public_docs(gem_path) do |docs|
        docs.each_value do |contents|
          refute_match SolidLens::PackageAudit::ABSOLUTE_LOCAL_LINK_PATTERN, contents
        end
      end
    end
  end

  def test_package_audit_verifies_built_gem
    SolidLens::PackageAudit.verify!(root: project_root)
  end

  private

  def with_built_package(&block)
    SolidLens::PackageAudit.with_built_package(root: project_root, &block)
  end

  def project_root
    File.expand_path("../..", __dir__)
  end
end
