#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))

require 'json'
require 'fileutils'
require 'tmpdir'
require 'time'
require 'shoko'

# Benchmarks the runtime state-store hot paths after the snapshot/copy reduction refactor.
module ShokoStateStoreHotPathBenchmark
  module_function

  NULL_LOGGER = Shoko::Core::Services::NullLogger.new
  TERMINAL_CAPABILITIES = Shoko::Adapters::Output::Terminal::NullTerminalCapabilities.new

  def run
    puts 'Shoko state store hot-path benchmark'
    puts "Ruby: #{RUBY_VERSION}"
    puts "Timestamp: #{Time.now.utc.iso8601}"
    puts

    results = []
    results << measure_simple_updates
    results << measure_large_updates
    results << measure_snapshot_loads

    puts JSON.pretty_generate(results)
  end

  def measure_simple_updates
    with_store(Shoko::Adapters::Runtime::SessionState::ObserverStateStore) do |store|
      {
        scenario: 'simple_updates',
        updates: 10_000,
        seconds: measure_updates(store: store, count: 10_000).round(4),
      }
    end
  end

  def measure_large_updates
    with_store(Shoko::Adapters::Runtime::SessionState::ObserverStateStore) do |store|
      seed_large_state(store)
      store_timing = measure_updates(store: store, count: 2_000)

      with_store(Shoko::Adapters::Runtime::SessionState::StateStore) do |base_store|
        seed_large_state(base_store)
        base_timing = measure_updates(store: base_store, count: 2_000)

        {
          scenario: 'large_updates',
          updates: 2_000,
          observer_seconds: store_timing.round(4),
          base_seconds: base_timing.round(4),
          slowdown_ratio: safe_ratio(store_timing, base_timing).round(2),
        }
      end
    end
  end

  def measure_snapshot_loads
    with_store(Shoko::Adapters::Runtime::SessionState::ObserverStateStore) do |store|
      seed_large_state(store)
      reader_store = Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter.new(store)

      {
        scenario: 'reader_snapshot_loads',
        loads: 2_000,
        seconds: measure_time do
          2_000.times { reader_store.load }
        end.round(4),
      }
    end
  end

  def with_store(store_class)
    Dir.mktmpdir do |dir|
      storage = config_storage_for(dir)
      store = store_class.new(
        config_storage: storage,
        terminal_capabilities: TERMINAL_CAPABILITIES,
        logger: NULL_LOGGER
      )
      yield store
    end
  end

  def config_storage_for(dir)
    config_dir = dir
    config_file = File.join(dir, 'config.json')
    Object.new.tap do |storage|
      storage.define_singleton_method(:config_dir) { config_dir }
      storage.define_singleton_method(:config_file) { config_file }
      storage.define_singleton_method(:ensure_config_dir) { FileUtils.mkdir_p(config_dir) }
      storage.define_singleton_method(:atomic_write) { |path, data| File.write(path, data) }
      storage.define_singleton_method(:read_file) { |path| File.exist?(path) ? File.read(path) : nil }
      storage.define_singleton_method(:file_exist?) { |path| File.exist?(path) }
    end
  end

  def seed_large_state(store)
    store.update(
      %i[reader annotations] => build_annotations,
      %i[reader page_map] => build_page_map
    )
  end

  def measure_updates(store:, count:)
    measure_time do
      count.times { |i| store.update(%i[reader current_page_index] => i) }
    end
  end

  def build_annotations
    Array.new(1_000) do |i|
      {
        id: i,
        text: "note #{i}",
        meta: { chapter: i % 20, line: i * 3 },
      }
    end
  end

  def build_page_map
    Array.new(2_000) do |i|
      {
        chapter_index: i % 20,
        start_line: i * 10,
        end_line: (i * 10) + 9,
      }
    end
  end

  def safe_ratio(lhs, rhs)
    return 0.0 if rhs.zero?

    lhs / rhs
  end

  def measure_time
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end
end

ShokoStateStoreHotPathBenchmark.run if $PROGRAM_NAME == __FILE__
