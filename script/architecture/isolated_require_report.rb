#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'rbconfig'
require 'tempfile'

root = File.expand_path('../..', __dir__)
lib_root = File.join(root, 'lib')
require_snippet = '$LOAD_PATH.unshift(ARGV[0]); require ARGV[1]'
timeout_seconds = 5
excluded = [
  File.join(lib_root, 'shoko.rb'),
  File.join(lib_root, 'shoko', 'composition', 'runtime_composition.rb'),
].freeze

files = Dir[File.join(lib_root, '**', '*.rb')].sort.reject { |path| excluded.include?(path) }

def run_isolated_require(lib_root, require_target, require_snippet, timeout_seconds)
  stdout_file = Tempfile.new('isolated-require-stdout')
  stderr_file = Tempfile.new('isolated-require-stderr')

  pid = Process.spawn(
    RbConfig.ruby,
    '-e',
    require_snippet,
    lib_root,
    require_target,
    out: stdout_file.path,
    err: stderr_file.path
  )

  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
  status = nil

  loop do
    _pid, status = Process.waitpid2(pid, Process::WNOHANG)
    break if status

    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      Process.kill('TERM', pid)
      sleep 0.05
      begin
        Process.kill('KILL', pid)
      rescue Errno::ESRCH
        nil
      end
      Process.waitpid2(pid)
      status = nil
      break
    end

    sleep 0.01
  rescue Errno::ECHILD
    break
  end

  {
    stdout: File.read(stdout_file.path),
    stderr: File.read(stderr_file.path),
    status: status,
  }
ensure
  stdout_file&.close!
  stderr_file&.close!
end

failures = files.filter_map do |path|
  require_target = path.delete_prefix("#{lib_root}/").sub(/\.rb\z/, '')
  result = run_isolated_require(lib_root, require_target, require_snippet, timeout_seconds)
  status = result[:status]
  next if status&.success?

  {
    path: path.delete_prefix("#{root}/"),
    require_target: require_target,
    status: status&.exitstatus,
    stdout: result[:stdout],
    stderr: if status.nil?
              "#{result[:stderr]}\nTimed out after #{timeout_seconds} seconds"
            else
              result[:stderr]
            end,
  }
end

puts JSON.pretty_generate(failures)
