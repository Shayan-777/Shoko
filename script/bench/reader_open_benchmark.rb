#!/usr/bin/env ruby
# frozen_string_literal: true

# End-to-end reader snappiness benchmark.
#
# Opens real books from the bench sandbox with `bin/shoko BOOK` on a PTY and
# measures:
#
#   * time to first readable paint;
#   * page-turn (l key) latency while the reader is rebuilding its page map
#     in the background — the "opened at a new terminal size" scenario;
#   * page-turn latency once everything is cached (fresh open).
#
# Page turns are detected by output volume: a turn repaints the content
# area (kilobytes after row-diffing), while spinner/status repaints are a
# couple of rows. The threshold is far from both, so the signal is stable.
#
# Usage: ruby script/bench/reader_open_benchmark.rb \
#          [--sandbox DIR] [--turns N] [--out PATH]

require 'json'
require 'optparse'
require_relative 'support/pty_session'
require_relative 'support/library_sandbox'

module ReaderOpenBenchmark
  ROWS = 56
  COLS = 220
  TURN_GAP = 0.08
  TURN_TIMEOUT = 15.0
  PAINT_THRESHOLD_BYTES = 2048

  DEFAULT_BOOKS = [
    'The Decline of the West An Abridged Edition (Oswald Spengler) (an abridged edition)).pdf',
    'Class Struggle A Political and Philosophical History (Domenico Losurdo).epub',
    'Как устроена экономика (Ха-Джун Чанг).fb2',
  ].freeze

  module_function

  def run(argv = ARGV)
    options = parse_options(argv)
    sandbox = ShokoBench::LibrarySandbox.new(root: options[:sandbox])
    raise "sandbox #{options[:sandbox]} is not prepared (run menu_responsiveness_benchmark first)" \
      unless sandbox.prepared? && sandbox.snapshot?

    report = { timestamp: Time.now.utc.iso8601, ruby: RUBY_VERSION, terminal: "#{COLS}x#{ROWS}", books: {} }
    DEFAULT_BOOKS.each do |name|
      path = File.join(sandbox.books_dir, name)
      next unless File.exist?(path)

      report[:books][name] = measure_book(sandbox, path, turns: options[:turns])
    end

    print_report(report)
    File.write(options[:out], JSON.pretty_generate(report)) if options[:out]
  end

  def parse_options(argv)
    options = { sandbox: '/tmp/shoko-bench-baseline', turns: 30, out: nil }
    OptionParser.new do |opts|
      opts.banner = 'Usage: reader_open_benchmark.rb [options]'
      opts.on('--sandbox DIR', 'Sandbox prepared by menu_responsiveness_benchmark') { |v| options[:sandbox] = v }
      opts.on('--turns N', Integer, 'page turns per phase (default: 30)') { |v| options[:turns] = [v, 4].max }
      opts.on('--out PATH', 'Write JSON report to PATH') { |v| options[:out] = v }
    end.parse!(argv)
    options
  end

  def measure_book(sandbox, path, turns:)
    sandbox.restore!
    sandbox.configure_warmup(enabled: false, last_paginated_size: nil)

    # Stale open: the snapshot only has page maps for the import-time size,
    # so opening at 220x56 triggers the background rebuild.
    stale = measure_session(sandbox, path, turns: turns)
    # Fresh open: the previous session left 220x56 page maps behind.
    fresh = measure_session(sandbox, path, turns: turns)

    { stale_open: stale, fresh_open: fresh }
  end

  def measure_session(sandbox, path, turns:)
    session = ShokoBench::PtySession.new(sandbox.env, sandbox.shoko_argv + [path], rows: ROWS, cols: COLS)
    spawn_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # Content-verified: the reader's status line (with the page counter "/")
    # arrives with the first frame even when page 1 is a near-empty cover.
    first_paint = session.wait_for(' / ', since: 0, timeout: 60.0)
    raise "reader never painted for #{path}" unless first_paint

    latencies = turn_loop(session, turns)
    settle = session.wait_for_quiet(quiet: 1.0, timeout: 300.0)
    session.stop(graceful_key: 'Q')
    {
      first_paint_ms: ((first_paint - spawn_time) * 1000.0).round(1),
      background_settled: settle,
      turn_ms: summarize(latencies),
    }
  end

  # Forward-only turns, verified by content: each press must repaint the
  # status bar with the incremented page counter, which changes only when
  # the page actually turned (spinner repaints re-emit the old counter and
  # can never fake a match).
  def turn_loop(session, turns)
    page = current_page(session)
    latencies = []
    turns.times do
      mark = session.mark
      pressed_at = session.write('l')
      page += 1
      arrived = session.wait_for(/(?<!\d)#{page} \/ \d/, since: mark, timeout: TURN_TIMEOUT)
      latencies << ((arrived || (pressed_at + TURN_TIMEOUT)) - pressed_at) * 1000.0
      sleep(TURN_GAP)
    end
    latencies
  end

  def current_page(session)
    sleep(0.3)
    counter = session.stripped_text[/(\d+) \/ \d+(?!.*\d+ \/ \d+)/m, 1]
    raise 'could not read the page counter from the status bar' unless counter

    Integer(counter)
  end

  def summarize(values)
    sorted = values.sort
    {
      p50: percentile(sorted, 50).round(1),
      p90: percentile(sorted, 90).round(1),
      p95: percentile(sorted, 95).round(1),
      max: sorted.last.round(1),
      samples: values.length,
    }
  end

  def percentile(sorted, rank)
    idx = ((rank / 100.0) * (sorted.length - 1)).round
    sorted[idx]
  end

  def print_report(report)
    puts
    puts "Reader open/turn latency (#{report[:terminal]})"
    report[:books].each do |name, phases|
      puts name
      phases.each do |phase, data|
        turn = data[:turn_ms]
        puts format('  %-11s first_paint=%8.1fms  turn p50=%7.1fms p95=%7.1fms max=%8.1fms settled=%s',
                    phase, data[:first_paint_ms], turn[:p50], turn[:p95], turn[:max], data[:background_settled])
      end
    end
  end
end

ReaderOpenBenchmark.run if $PROGRAM_NAME == __FILE__
