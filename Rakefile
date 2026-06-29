# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"
require_relative "lib/solid_lens/package_audit"

Rake::TestTask.new(:test) do |test|
  test.libs << "test"
  test.pattern = "test/**/*_test.rb"
end

namespace :package do
  desc "Build the gem and verify the packaged SolidLens command surface"
  task :verify do
    SolidLens::PackageAudit.verify!(root: __dir__)
  end
end

desc "Run the default verification plus packaged gem checks"
task verify: %i[test standard package:verify]

task default: %i[test standard]
