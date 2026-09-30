# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new do |task|
  task.patterns = %w[exe lib spec rakelib Rakefile Gemfile locallingo.gemspec]
end

desc "Build gem and verify contents"
task :build do
  sh("gem build locallingo.gemspec --strict")
  gem_file = Dir["locallingo-*.gem"].first
  abort "Gem file not found after build" unless gem_file

  sh("gem unpack #{gem_file} --target /tmp/locallingo-verify")
  puts "\n=== Gem contents ==="
  sh("find /tmp/locallingo-verify -type f | sort")
  sh("rm -rf /tmp/locallingo-verify #{gem_file}")
end

# `rake release[X.Y.Z]` lives in rakelib/release.rake (the zoolutions release
# kit, shared across the gems); `bin/release` is its interactive front door.

task default: %i[spec rubocop]
