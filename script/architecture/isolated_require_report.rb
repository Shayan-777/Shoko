#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'

root = File.expand_path('../..', __dir__)
lib_root = File.join(root, 'lib')
excluded = [
  File.join(lib_root, 'shoko.rb'),
  File.join(lib_root, 'shoko', 'bootstrap', 'runtime_bootstrap.rb'),
].freeze

files = Dir[File.join(lib_root, '**', '*.rb')].sort.reject { |path| excluded.include?(path) }

failures = files.filter_map do |path|
  require_target = path.delete_prefix("#{lib_root}/").sub(/\.rb\z/, '')
  stdout, stderr, status = Open3.capture3(
    'ruby',
    '-e',
    '$LOAD_PATH.unshift(ARGV[0]); require ARGV[1]',
    lib_root,
    require_target
  )
  next if status.success?

  {
    path: path.delete_prefix("#{root}/"),
    require_target: require_target,
    status: status.exitstatus,
    stdout: stdout,
    stderr: stderr,
  }
end

puts JSON.pretty_generate(failures)
