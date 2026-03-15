#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'time'
require 'shoko'
require_relative 'support/runtime_setup'

RUNTIME_CONFIG = ShokoBench::RuntimeSetup.configure!

module SidebarToggleLayoutBenchmark
  module_function

  WIDTH = 120
  HEIGHT = 40
  TOGGLES = 20

  Chapter = Struct.new(:lines, :title, keyword_init: true)

  class FakeDocument
    def initialize(chapters)
      @chapters = chapters
    end

    def chapter_count
      @chapters.length
    end

    def get_chapter(index)
      @chapters[index]
    end
  end

  class ConfigReader
    attr_accessor :view_mode, :line_spacing

    def initialize
      @view_mode = :single
      @line_spacing = :normal
    end

    def page_numbering_mode
      :dynamic
    end
  end

  class ReaderState
    attr_accessor :sidebar_visible, :current_page_index, :current_chapter

    def initialize
      @sidebar_visible = false
      @current_page_index = 0
      @current_chapter = 0
    end

    def sidebar_visible?
      @sidebar_visible == true
    end
  end

  class StateWriter
    def initialize(reader_state)
      @reader_state = reader_state
    end

    def update_pagination_state(**_attrs); end

    def update_page(current_page_index:)
      @reader_state.current_page_index = current_page_index
    end
  end

  def run
    puts 'Shoko sidebar toggle benchmark (dynamic pagination)'
    puts "Ruby: #{RUBY_VERSION}"
    puts "Timestamp: #{Time.now.utc.iso8601}"
    puts "Toggles per scenario: #{TOGGLES}"
    puts

    baseline_ms = benchmark_rebuild_toggle
    optimized_ms = benchmark_switch_toggle
    speedup = optimized_ms.positive? ? (baseline_ms / optimized_ms) : Float::INFINITY

    puts format('%-36s %10.2f ms', 'Baseline (full rebuild):', baseline_ms)
    puts format('%-36s %10.2f ms', 'Optimized (variant switch):', optimized_ms)
    puts format('%-36s %10.2fx', 'Speedup:', speedup)
  end

  def benchmark_rebuild_toggle
    fixture = build_fixture
    warmup do
      toggle_sidebar(fixture.reader_state)
      fixture.service.build_dynamic_map!(
        WIDTH,
        HEIGHT,
        fixture.doc,
        config_reader: fixture.config_reader,
        sidebar_visible: fixture.reader_state.sidebar_visible?
      )
    end

    measure do
      TOGGLES.times do
        toggle_sidebar(fixture.reader_state)
        fixture.service.build_dynamic_map!(
          WIDTH,
          HEIGHT,
          fixture.doc,
          config_reader: fixture.config_reader,
          sidebar_visible: fixture.reader_state.sidebar_visible?
        )
      end
    end
  end

  def benchmark_switch_toggle
    fixture = build_fixture
    warmup do
      toggle_sidebar(fixture.reader_state)
      fixture.service.switch_dynamic_layout_variant!(
        WIDTH,
        HEIGHT,
        fixture.doc,
        sidebar_visible: fixture.reader_state.sidebar_visible?,
        reader_state_reader: fixture.reader_state
      )
    end

    measure do
      TOGGLES.times do
        toggle_sidebar(fixture.reader_state)
        fixture.service.switch_dynamic_layout_variant!(
          WIDTH,
          HEIGHT,
          fixture.doc,
          sidebar_visible: fixture.reader_state.sidebar_visible?,
          reader_state_reader: fixture.reader_state
        )
      end
    end
  end

  Fixture = Struct.new(:service, :doc, :config_reader, :reader_state, :state_writer, keyword_init: true)

  def build_fixture
    config_reader = ConfigReader.new
    reader_state = ReaderState.new
    state_writer = StateWriter.new(reader_state)
    service = Shoko::Application::Services::Pagination::PageCalculatorService.new(
      text_metrics: Shoko::Adapters::Output::Terminal::TextMetrics,
      display_capabilities: Shoko::Adapters::Output::Kitty::DisplayCapabilities.new,
      instrumentation: Shoko::Core::Services::NullInstrumentation.new,
      config_reader: config_reader,
      layout_service: Shoko::Application::Services::LayoutService.new
    )

    doc = FakeDocument.new([
                             Chapter.new(
                               title: 'Synthetic',
                               lines: Array.new(3_000) { |i| "Line #{i}: #{'lorem ipsum dolor sit amet ' * 4}" }
                             )
                           ])

    service.build_dynamic_map!(
      WIDTH,
      HEIGHT,
      doc,
      config_reader: config_reader,
      sidebar_visible: reader_state.sidebar_visible?
    )

    Fixture.new(
      service: service,
      doc: doc,
      config_reader: config_reader,
      reader_state: reader_state,
      state_writer: state_writer
    )
  end

  def toggle_sidebar(reader_state)
    reader_state.sidebar_visible = !reader_state.sidebar_visible?
  end

  def warmup
    3.times { yield }
  end

  def measure
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ((finish - start) * 1000.0)
  end
end

SidebarToggleLayoutBenchmark.run if $PROGRAM_NAME == __FILE__
