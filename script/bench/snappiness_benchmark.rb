#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'time'
require 'json'
require 'tmpdir'
require 'shoko'

module SnappinessBenchmark
  module_function

  Metrics = Shoko::Adapters::Output::Terminal::TextMetrics
  WrappingService = Shoko::Adapters::Output::Formatting::WrappingService
  LineTokenizer = Shoko::Adapters::Output::Formatting::FormattingService::LineAssembler::Tokenizer
  LineGeometryBuilder = Shoko::Adapters::Output::Ui::Components::Reading::LineGeometryBuilder
  Frame = Shoko::Adapters::Output::Terminal::TerminalBuffer::Frame
  LineContentComposer = Shoko::Adapters::Output::Ui::Components::Reading::LineContentComposer
  ManifestShaFinder = Shoko::Adapters::Storage::BookCachePipeline.send(:const_get, :ManifestShaFinder)
  CacheStore = Shoko::Adapters::Storage::JsonCacheStore

  def run
    puts "Shoko snappiness benchmark"
    puts "Ruby: #{RUBY_VERSION}"
    puts "Timestamp: #{Time.now.utc.iso8601}"
    puts

    sample_lines = [
      "The quick brown fox jumps over the lazy dog.",
      "\e[31mANSI\e[0m mix with\ttabs and emoji 😀😀😀.",
      "日本語の文章を含むテキスト with mixed-width glyphs.",
      "supercalifragilisticexpialidocious" * 2,
      "e\u0301 cafe\u0301 and combining marks.",
      "# Heading with punctuation: [link](https://example.com)"
    ]

    paragraph = (sample_lines * 120).join(' ')
    block_text = (sample_lines * 30).join(' ')
    lines_for_windows = build_window_lines

    results = []

    results << measure_cache_toggle_scenario(
      name: 'TextMetrics.visible_length',
      baseline_label: 'cache=off',
      optimized_label: 'cache=on'
    ) do |cache_enabled|
      Metrics.clear_visible_length_cache
      Metrics.with_visible_length_cache(enabled: cache_enabled) do
        measure_iterations(25_000) { |i| Metrics.visible_length(sample_lines[i % sample_lines.length]) }
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'TextMetrics.visible_length ASCII long',
      baseline_label: 'ascii-fast=off',
      optimized_label: 'ascii-fast=on'
    ) do |ascii_fast_enabled|
      long_ascii = ('The quick brown fox jumps over the lazy dog 1234567890 ' * 8).freeze
      Metrics.with_ascii_fast_path(enabled: ascii_fast_enabled) do
        Metrics.with_visible_length_cache(enabled: false) do
          measure_iterations(15_000) { Metrics.visible_length(long_ascii) }
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'TextMetrics.truncate_to ASCII',
      baseline_label: 'ascii-fast=off',
      optimized_label: 'ascii-fast=on'
    ) do |ascii_fast_enabled|
      long_ascii = ('The quick brown fox jumps over the lazy dog 1234567890 ' * 8).freeze
      Metrics.with_ascii_fast_path(enabled: ascii_fast_enabled) do
        Metrics.with_visible_length_cache(enabled: true) do
          measure_iterations(15_000) { Metrics.truncate_to(long_ascii, 80) }
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'TextMetrics.wrap_plain_text',
      baseline_label: 'cache=off',
      optimized_label: 'cache=on'
    ) do |cache_enabled|
      Metrics.clear_visible_length_cache
      Metrics.clear_wrap_plain_text_cache
      Metrics.with_wrap_plain_text_cache(enabled: false) do
        Metrics.with_visible_length_cache(enabled: cache_enabled) do
          measure_iterations(180) { Metrics.wrap_plain_text(paragraph, 70) }
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'TextMetrics.wrap_plain_text result cache',
      baseline_label: 'wrap-cache=off',
      optimized_label: 'wrap-cache=on'
    ) do |wrap_cache_enabled|
      repeated_line = (sample_lines * 6).join(' ')
      Metrics.clear_visible_length_cache
      Metrics.clear_wrap_plain_text_cache
      Metrics.with_visible_length_cache(enabled: true) do
        Metrics.with_wrap_plain_text_cache(enabled: wrap_cache_enabled) do
          measure_iterations(2_000) { Metrics.wrap_plain_text(repeated_line, 70) }
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'LineAssembler.build',
      baseline_label: 'cache=off',
      optimized_label: 'cache=on'
    ) do |cache_enabled|
      blocks = build_blocks(block_text)
      Metrics.clear_visible_length_cache
      LineTokenizer.with_tokenize_cache(enabled: false) do
        Metrics.with_visible_length_cache(enabled: cache_enabled) do
          measure_iterations(40) do
            assembler = Shoko::Adapters::Output::Formatting::FormattingService::LineAssembler.new(72)
            assembler.build(blocks)
          end
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'LineAssembler::Tokenizer.tokenize cache',
      baseline_label: 'token-cache=off',
      optimized_label: 'token-cache=on'
    ) do |token_cache_enabled|
      renderable_image_src = ->(_src) { false }
      text = (sample_lines * 30).join(' ')
      segments = [Shoko::Core::Models::TextSegment.new(text: text, styles: { bold: true })]

      LineTokenizer.clear_tokenize_cache
      LineTokenizer.with_tokenize_cache(enabled: token_cache_enabled) do
        measure_iterations(600) do
          LineTokenizer.tokenize(segments, image_rendering: false, renderable_image_src: renderable_image_src)
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'LineAssembler.build tokenize cache',
      baseline_label: 'token-cache=off',
      optimized_label: 'token-cache=on'
    ) do |token_cache_enabled|
      blocks = build_blocks(block_text)
      Metrics.clear_visible_length_cache
      LineTokenizer.clear_tokenize_cache
      Metrics.with_visible_length_cache(enabled: true) do
        LineTokenizer.with_tokenize_cache(enabled: token_cache_enabled) do
          measure_iterations(40) do
            assembler = Shoko::Adapters::Output::Formatting::FormattingService::LineAssembler.new(72)
            assembler.build(blocks)
          end
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'LineAssembler.build token width hints',
      baseline_label: 'width-hints=off',
      optimized_label: 'width-hints=on'
    ) do |width_hints_enabled|
      blocks = build_blocks(block_text)
      Metrics.clear_visible_length_cache
      LineTokenizer.clear_tokenize_cache
      Metrics.with_visible_length_cache(enabled: true) do
        LineTokenizer.with_tokenize_cache(enabled: true) do
          LineTokenizer.with_token_width_hints(enabled: width_hints_enabled) do
            measure_iterations(40) do
              assembler = Shoko::Adapters::Output::Formatting::FormattingService::LineAssembler.new(72)
              assembler.build(blocks)
            end
          end
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'LineAssembler.build token pipeline',
      baseline_label: 'token-cache=off,width-hints=off',
      optimized_label: 'token-cache=on,width-hints=on'
    ) do |token_pipeline_enabled|
      blocks = build_blocks(block_text)
      Metrics.clear_visible_length_cache
      LineTokenizer.clear_tokenize_cache
      Metrics.with_visible_length_cache(enabled: true) do
        LineTokenizer.with_token_width_hints(enabled: token_pipeline_enabled) do
          LineTokenizer.with_tokenize_cache(enabled: token_pipeline_enabled) do
            measure_iterations(40) do
              assembler = Shoko::Adapters::Output::Formatting::FormattingService::LineAssembler.new(72)
              assembler.build(blocks)
            end
          end
        end
      end
    end

    results << measure_range_cache_scenario(lines_for_windows)

    results << measure_cache_toggle_scenario(
      name: 'LineGeometryBuilder.build (repeated text)',
      baseline_label: 'cell-cache=off',
      optimized_label: 'cell-cache=on'
    ) do |cache_enabled|
      builder = LineGeometryBuilder.new
      plain = ('The quick brown fox jumps over the lazy dog 日本語 😀 ' * 2).freeze
      LineGeometryBuilder.with_cell_cache(enabled: cache_enabled) do
        measure_iterations(120_000) do |i|
          builder.build(
            page_id: 1,
            column_id: 'main',
            row: (i % 40) + 1,
            col: 1,
            line_offset: i,
            plain_text: plain,
            styled_text: plain
          )
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'TerminalBuffer::Frame.write ASCII',
      baseline_label: 'fast-ascii=off',
      optimized_label: 'fast-ascii=on'
    ) do |fast_ascii_enabled|
      line = ('The quick brown fox jumps over the lazy dog 1234567890 ' * 3).freeze
      Frame.with_fast_ascii_write(enabled: fast_ascii_enabled) do
        measure_iterations(80) do
          frame = Frame.new(120, 40)
          40.times { |row| frame.write(row + 1, 1, line) }
          frame.rendered_rows
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'LineContentComposer.compose (repeated line)',
      baseline_label: 'compose-cache=off',
      optimized_label: 'compose-cache=on'
    ) do |compose_cache_enabled|
      composer = LineContentComposer.new
      config = Struct.new(:highlight_keywords, :highlight_quotes, keyword_init: true).new(
        highlight_keywords: true,
        highlight_quotes: true
      )
      segment_text = 'The quick brown fox jumps over the lazy dog 日本語 😀 '
      segments = 6.times.map do |idx|
        Shoko::Core::Models::TextSegment.new(text: segment_text, styles: idx.even? ? { bold: true } : {})
      end
      line = Shoko::Core::Models::DisplayLine.new(text: segments.map(&:text).join, segments: segments, metadata: {})

      LineContentComposer.with_compose_cache(enabled: compose_cache_enabled) do
        LineContentComposer.clear_compose_cache
        measure_iterations(60_000) do
          composer.compose(line, 80, config)
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'ManifestShaFinder.sha (large manifest)',
      baseline_label: 'fast-scan=off',
      optimized_label: 'fast-scan=on'
    ) do |fast_scan_enabled|
      rows = build_manifest_rows
      target = rows[20_000]
      source_path = target['source_path']
      source_mtime = Time.at(target['source_mtime'].to_f)
      source_size = target['source_size_bytes']

      ManifestShaFinder.with_fast_scan(enabled: fast_scan_enabled) do
        measure_iterations(180) do
          ManifestShaFinder.new(
            rows: rows,
            source_path: source_path,
            source_mtime: source_mtime,
            source_size_bytes: source_size
          ).sha
        end
      end
    end

    results << measure_cache_toggle_scenario(
      name: 'JsonCacheStore.manifest_rows (repeated)',
      baseline_label: 'rows-cache=off',
      optimized_label: 'rows-cache=on'
    ) do |rows_cache_enabled|
      rows = build_manifest_rows

      Dir.mktmpdir('shoko-bench-manifest') do |dir|
        path = File.join(dir, CacheStore::MANIFEST_FILENAME)
        File.write(path, JSON.generate(rows))

        CacheStore.clear_manifest_rows_cache(dir)
        CacheStore.with_manifest_rows_cache(enabled: rows_cache_enabled) do
          measure_iterations(100) do
            CacheStore.manifest_rows(dir)
          end
        end
      ensure
        CacheStore.clear_manifest_rows_cache(dir)
      end
    end

    print_results(results)
  end

  def measure_cache_toggle_scenario(name:, baseline_label:, optimized_label:)
    baseline_ms = yield(false)
    optimized_ms = yield(true)

    {
      name: name,
      baseline_label: baseline_label,
      optimized_label: optimized_label,
      baseline_ms: baseline_ms,
      optimized_ms: optimized_ms,
    }
  end

  def measure_range_cache_scenario(lines)
    queries = Array.new(140) { |i| { start: 1000 + (i * 8), length: 36 } }

    baseline_ms = with_env('SHOKO_DISABLE_WINDOW_RANGE_CACHE', '1') do
      service = WrappingService.new(
        text_metrics: Metrics,
        async_executor: Shoko::Core::Services::InlineExecutor.new
      )
      Metrics.clear_visible_length_cache
      Metrics.with_visible_length_cache(enabled: true) do
        service.wrap_window(lines, 0, 72, 1000, 2600)
        measure_iterations(queries.length) do |i|
          q = queries[i]
          service.wrap_window(lines, 0, 72, q[:start], q[:length])
        end
      end
    end

    optimized_ms = with_env('SHOKO_DISABLE_WINDOW_RANGE_CACHE', '0') do
      service = WrappingService.new(
        text_metrics: Metrics,
        async_executor: Shoko::Core::Services::InlineExecutor.new
      )
      Metrics.clear_visible_length_cache
      Metrics.with_visible_length_cache(enabled: true) do
        service.wrap_window(lines, 0, 72, 1000, 2600)
        measure_iterations(queries.length) do |i|
          q = queries[i]
          service.wrap_window(lines, 0, 72, q[:start], q[:length])
        end
      end
    end

    {
      name: 'WrappingService.wrap_window prefetch reuse',
      baseline_label: 'range-cache=off',
      optimized_label: 'range-cache=on',
      baseline_ms: baseline_ms,
      optimized_ms: optimized_ms,
    }
  end

  def build_blocks(text)
    segment = Shoko::Core::Models::TextSegment.new(text: text, styles: {})
    block = Shoko::Core::Models::ContentBlock.new(type: :paragraph, segments: [segment], level: 0, metadata: {})
    Array.new(20) { block }
  end

  def build_window_lines
    sample = "The quick brown fox jumps over the lazy dog 日本語 😀 \e[31mansi\e[0m "
    Array.new(7000) { |i| "#{i} #{sample * 4}" }
  end

  def build_manifest_rows
    Array.new(25_000) do |i|
      {
        'source_path' => "/library/book_#{i}.epub",
        'source_mtime' => 1_700_000_000.0 + i,
        'source_size_bytes' => 100_000 + i,
        'source_fingerprint' => nil,
        'updated_at' => 1_700_000_100.0 + i,
        'source_sha' => format('%064x', i + 1),
      }
    end
  end

  def measure_iterations(iterations)
    warmup(iterations) { |i| yield(i) }
    gc_compact

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times { |i| yield(i) }
    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ((finish - start) * 1000.0)
  end

  def warmup(iterations)
    warmup_iterations = [iterations / 10, 1].max
    warmup_iterations.times { |i| yield(i) }
  end

  def gc_compact
    GC.start(full_mark: true, immediate_sweep: true)
  rescue ArgumentError
    GC.start
  end

  def with_env(key, value)
    previous = ENV[key]
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
    yield
  ensure
    if previous.nil?
      ENV.delete(key)
    else
      ENV[key] = previous
    end
  end

  def print_results(results)
    puts format('%-44s %14s %14s %10s', 'Scenario', 'Baseline (ms)', 'Optimized (ms)', 'Speedup')
    puts '-' * 88

    results.each do |result|
      baseline_ms = result[:baseline_ms]
      optimized_ms = result[:optimized_ms]
      speedup = optimized_ms.positive? ? (baseline_ms / optimized_ms) : Float::INFINITY

      puts format('%-44s %14.2f %14.2f %9.2fx', result[:name], baseline_ms, optimized_ms, speedup)
      puts format("  baseline: %s, optimized: %s", result[:baseline_label], result[:optimized_label])
    end
  end
end

SnappinessBenchmark.run
