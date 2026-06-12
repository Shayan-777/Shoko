#!/usr/bin/env ruby
# frozen_string_literal: true

# Imports every supported book under ARGV[0] into the cache the current XDG
# environment points at, printing one JSON line per imported book with the
# time it took (import + readiness pagination at the current terminal size).
#
# Run with HOME / XDG_CONFIG_HOME / XDG_CACHE_HOME pointed at a sandbox; the
# bench harness spawns this in a child process for exactly that reason.

$LOAD_PATH.unshift(File.expand_path('../../../lib', __dir__))
require 'json'
require 'shoko'

books_dir = ARGV.fetch(0) { abort('usage: import_books.rb BOOKS_DIR') }

context = Shoko::Composition::ContainerFactory.build_cli_folder_import_context(log_config: {})
workflow = context.workflow
report = workflow.discover(books_dir, recursive: true, skip_hidden: true)

monotonic = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
started = monotonic.call
last = started

workflow.import(report.documents) do |done: nil, total: nil, path: nil, status: nil, message: nil, progress: nil|
  _ = message
  _ = progress
  next unless %i[imported skipped failed].include?(status)

  now = monotonic.call
  puts({ event: 'book', path: path, status: status, seconds: (now - last).round(3),
         done: done, total: total }.to_json)
  $stdout.flush
  last = now
end

puts({ event: 'total', books: report.total_count, seconds: (monotonic.call - started).round(3) }.to_json)
