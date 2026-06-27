# frozen_string_literal: true

require_relative "lib/solid_lens/version"

Gem::Specification.new do |spec|
  spec.name = "solid_lens"
  spec.version = SolidLens::VERSION
  spec.authors = ["Allan Flavio"]

  spec.summary = "Causal diagnostics for Solid Queue production health."
  spec.description = "SolidLens inspects Solid Queue configuration, database capacity, lock support, queue shape, lag, bloat, and critical query plans."
  spec.homepage = "https://github.com/Defyland/solid_lens"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "exe/*", "docs/specs/*.md", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  end
  spec.bindir = "exe"
  spec.executables = ["solid_lens"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.1", "< 9.0"
  spec.add_dependency "activesupport", ">= 7.1", "< 9.0"
  spec.add_dependency "railties", ">= 7.1", "< 9.0"
  spec.add_dependency "solid_queue", ">= 1.4", "< 2.0"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "parallel", "< 2.0"
  spec.add_development_dependency "pg", "~> 1.5"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "sqlite3", "~> 2.5"
  spec.add_development_dependency "standard", "~> 1.44"
  spec.add_development_dependency "trilogy", "~> 2.7"
end
