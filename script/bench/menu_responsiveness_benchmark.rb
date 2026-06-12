#!/usr/bin/env ruby
# frozen_string_literal: true

# End-to-end menu snappiness benchmark.
#
# Spawns the real `bin/shoko` on a PTY against a sandboxed library and
# measures what the user actually feels:
#
#   * keypress -> paint latency in the library menu, verified by content:
#     each j/k press must repaint the details panel's unique "Book N of M"
#     line, which changes only when the selection moves (so background
#     spinner repaints can never fake a match);
#   * the same latency while the library pre-pagination warmup is rebuilding
#     page maps in the background (the "recalculating on startup" scenario);
#   * paint gaps while the warmup toast spinner should animate at 10 Hz
#     (a starved UI shows multi-second gaps);
#   * warmup wall time until the new size signature is persisted.
#
# Usage: ruby script/bench/menu_responsiveness_benchmark.rb \
#          [--presses N] [--sandbox DIR] [--keep] [--out PATH]

require 'English'
require 'json'
require 'optparse'
require 'tmpdir'
require_relative 'support/pty_session'
require_relative 'support/library_sandbox'

module MenuResponsivenessBenchmark
  ROWS = 56
  COLS = 220
  SIZE_SIGNATURE = "#{COLS}x#{ROWS}".freeze
  STALE_SIGNATURE = '80x24'
  PRESS_GAP = 0.08
  PRESS_TIMEOUT = 15.0
  WARMUP_SETTLE = 2.0 # LibraryPrepaginationWarmup startup_settle default
  WARMUP_TIMEOUT = 600.0

  module_function

  def run(argv = ARGV)
    options = parse_options(argv)
    sandbox = build_sandbox(options)

    unless sandbox.snapshot?
      prewarm(sandbox)
      sandbox.snapshot!
    end
    idle = measure_phase(sandbox, busy: false, presses: options[:presses])
    busy = measure_phase(sandbox, busy: true, presses: options[:presses])

    report = build_report(sandbox, idle, busy)
    print_report(report)
    File.write(options[:out], JSON.pretty_generate(report)) if options[:out]
  ensure
    cleanup_sandbox(sandbox, options)
  end

  def parse_options(argv)
    options = { presses: 40, sandbox: nil, keep: false, out: nil }
    OptionParser.new do |opts|
      opts.banner = 'Usage: menu_responsiveness_benchmark.rb [options]'
      opts.on('--presses N', Integer, 'j/k presses per phase (default: 40)') { |v| options[:presses] = [v, 4].max }
      opts.on('--sandbox DIR', 'Reuse/create sandbox at DIR instead of a tmpdir') { |v| options[:sandbox] = v }
      opts.on('--keep', 'Keep the sandbox directory afterwards') { options[:keep] = true }
      opts.on('--out PATH', 'Write JSON report to PATH') { |v| options[:out] = v }
    end.parse!(argv)
    options
  end

  def build_sandbox(options)
    root = options[:sandbox] || Dir.mktmpdir('shoko-bench-')
    options[:created_tmpdir] = options[:sandbox].nil?
    sandbox = ShokoBench::LibrarySandbox.new(root: root)
    if sandbox.prepared?
      warn "sandbox: reusing #{root}"
      sandbox.load_import_timings
    else
      warn "sandbox: preparing #{root} (one-time import)"
      sandbox.prepare!
    end
    sandbox
  end

  # One throwaway menu run so the display-metadata cache and the library scan
  # cache are warm; measured runs then see no first-run repaint noise.
  def prewarm(sandbox)
    sandbox.configure_warmup(enabled: false, last_paginated_size: nil)
    session = spawn_menu(sandbox)
    session.wait_for_quiet(quiet: 1.5, timeout: 30.0)
    session.stop(graceful_key: 'Q')
  end

  def spawn_menu(sandbox)
    ShokoBench::PtySession.new(sandbox.env, sandbox.shoko_argv, rows: ROWS, cols: COLS)
  end

  def measure_phase(sandbox, busy:, presses:)
    sandbox.restore!
    sandbox.configure_warmup(
      enabled: true,
      last_paginated_size: busy ? STALE_SIGNATURE : SIZE_SIGNATURE
    )
    session = spawn_menu(sandbox)
    spawn_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    open_details(session, busy: busy)
    sleep_until(spawn_time + WARMUP_SETTLE + 0.5) if busy

    latencies = press_loop(session, presses)
    completion = busy ? await_warmup(sandbox, session, spawn_time) : {}

    session.stop(graceful_key: 'Q')
    { latencies_ms: latencies, **completion }
  end

  # Navigate main menu -> Library screen -> open the details inspector.
  # Content-triggered (not quiet-triggered) so it completes inside the
  # warmup's startup-settle window even when the busy phase will starve the
  # UI right afterwards.
  def open_details(session, busy:)
    raise 'menu never painted' unless session.wait_for('Browse Library', since: 0, timeout: 20.0)

    sleep(0.3)
    mark = session.mark
    session.write("j\r")
    raise "library screen did not open (busy=#{busy})" unless session.wait_for('CACHED BOOKS', since: mark,
                                                                                               timeout: 30.0)

    mark = session.mark
    session.write(' ')
    arrived = session.wait_for('Book 1 of', since: mark, timeout: 30.0)
    raise "details panel did not open (busy=#{busy})" unless arrived
  end

  # Alternate j/k so the details panel's "Book N of M" line flips between
  # two known values; the arrival of the new value is the paint signal.
  def press_loop(session, presses)
    selection = 0
    latencies = []
    presses.times do |i|
      key = i.even? ? 'j' : 'k'
      selection = i.even? ? selection + 1 : selection - 1
      mark = session.mark
      pressed_at = session.write(key)
      arrived = session.wait_for("Book #{selection + 1} of", since: mark, timeout: PRESS_TIMEOUT)
      latencies << ((arrived || (pressed_at + PRESS_TIMEOUT)) - pressed_at) * 1000.0
      sleep(PRESS_GAP)
    end
    latencies
  end

  # After the press window, sit idle until the warmup persists the new size
  # signature; meanwhile the toast spinner should repaint at 10 Hz, so paint
  # gaps here measure pure UI starvation.
  def await_warmup(sandbox, session, spawn_time)
    gap_mark = session.mark
    deadline = spawn_time + WARMUP_TIMEOUT
    finished = nil
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      if sandbox.current_config['last_paginated_size'] == SIZE_SIGNATURE
        finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break
      end
      sleep(0.25)
    end

    gaps = session.paint_gaps(since: gap_mark).map { |gap| gap * 1000.0 }
    {
      warmup_wall_s: finished ? (finished - spawn_time).round(2) : nil,
      warmup_finished: !finished.nil?,
      spinner_gap_ms: {
        p50: percentile(gaps, 50)&.round(1),
        p95: percentile(gaps, 95)&.round(1),
        max: gaps.max&.round(1),
      },
    }
  end

  def build_report(sandbox, idle, busy)
    {
      timestamp: Time.now.utc.iso8601,
      ruby: RUBY_VERSION,
      terminal: "#{COLS}x#{ROWS}",
      books: sandbox.import_timings.count { |t| t['event'] == 'book' },
      import_timings: sandbox.import_timings,
      idle: summarize(idle),
      busy: summarize(busy),
    }
  end

  def summarize(phase)
    values = phase[:latencies_ms]
    phase.merge(
      latency_ms: {
        p50: percentile(values, 50)&.round(1),
        p90: percentile(values, 90)&.round(1),
        p95: percentile(values, 95)&.round(1),
        max: values.max&.round(1),
      }
    ).except(:latencies_ms).merge(samples: values.length, latencies_ms: values.map { |v| v.round(1) })
  end

  def percentile(values, rank)
    return nil if values.nil? || values.empty?

    sorted = values.sort
    idx = ((rank / 100.0) * (sorted.length - 1)).round
    sorted[idx]
  end

  def print_report(report)
    puts
    puts "Menu responsiveness (#{report[:terminal]}, #{report[:books]} books)"
    %i[idle busy].each do |phase|
      data = report[phase]
      lat = data[:latency_ms]
      line = format('%-5s press->paint  p50=%7.1fms  p90=%7.1fms  p95=%7.1fms  max=%8.1fms',
                    phase, lat[:p50], lat[:p90], lat[:p95], lat[:max])
      puts line
    end
    busy = report[:busy]
    if busy[:spinner_gap_ms]
      gap = busy[:spinner_gap_ms]
      puts format('busy  spinner gaps  p50=%7.1fms  p95=%7.1fms  max=%8.1fms', gap[:p50], gap[:p95], gap[:max])
    end
    puts "busy  warmup wall time: #{busy[:warmup_wall_s] ? "#{busy[:warmup_wall_s]}s" : "DID NOT FINISH within #{WARMUP_TIMEOUT.to_i}s"}"
  end

  def sleep_until(deadline)
    delta = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sleep(delta) if delta.positive?
  end

  def cleanup_sandbox(sandbox, options)
    return unless sandbox
    return if options[:keep] || !options[:created_tmpdir]

    FileUtils.remove_entry(sandbox.root)
  end
end

MenuResponsivenessBenchmark.run if $PROGRAM_NAME == __FILE__
