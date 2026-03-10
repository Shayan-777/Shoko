# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::PageCalculatorService do
  class CountingTextMetrics
    attr_reader :wrap_calls

    def initialize
      @wrap_calls = 0
    end

    def wrap_plain_text(text, width)
      @wrap_calls += 1
      col_width = [width.to_i, 1].max
      text.to_s.scan(/.{1,#{col_width}}/)
    end
  end

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

  class MutableReaderState
    attr_accessor :sidebar_visible, :current_page_index, :current_chapter

    def initialize(sidebar_visible:, current_page_index:, current_chapter:)
      @sidebar_visible = sidebar_visible
      @current_page_index = current_page_index
      @current_chapter = current_chapter
    end

    def sidebar_visible?
      @sidebar_visible == true
    end
  end

  let(:text_metrics) { CountingTextMetrics.new }
  let(:display_capabilities) { instance_double('DisplayCapabilities', kitty_images_enabled?: false) }
  let(:instrumentation) { instance_double('Instrumentation') }
  let(:config_reader) do
    instance_double('ConfigReader',
                    page_numbering_mode: :dynamic,
                    view_mode: :single,
                    line_spacing: :normal,
                    kitty_images: false)
  end
  let(:reader_state_reader) do
    MutableReaderState.new(sidebar_visible: false, current_page_index: 0, current_chapter: 0)
  end
  let(:layout_service) { Shoko::Application::Services::LayoutService.new }

  before do
    allow(instrumentation).to receive(:measure) { |_metric, &block| block&.call }
    allow(instrumentation).to receive(:annotate)
  end

  def build_service
    described_class.new(
      text_metrics: text_metrics,
      display_capabilities: display_capabilities,
      instrumentation: instrumentation,
      config_reader: config_reader,
      layout_service: layout_service
    )
  end

  it 'precomputes sidebar variant and switches without rebuilding wrapped lines' do
    long_line = 'x' * 60
    doc = FakeDocument.new([Chapter.new(lines: [long_line], title: 'One')])
    service = build_service

    payload = service.build_dynamic_map!(80, 24, doc,
                                         config_reader: config_reader,
                                         sidebar_visible: false)
    expect(payload[:total_pages]).to eq(service.total_pages)
    base_lines = service.pages_data.first[:lines]
    wrap_calls_after_build = text_metrics.wrap_calls

    allow(service).to receive(:formatted_lines?).and_return(true)
    reader_state_reader.current_page_index = 0
    reader_state_reader.sidebar_visible = true
    result = service.switch_dynamic_layout_variant!(
      80,
      24,
      doc,
      sidebar_visible: true,
      reader_state_reader: reader_state_reader
    )
    expect(result[:status]).to eq(:switched)
    sidebar_lines = service.pages_data.first[:lines]

    expect(sidebar_lines.length).to be > base_lines.length
    expect(text_metrics.wrap_calls).to eq(wrap_calls_after_build)
  end

  it 'maps current line offset to a valid page in the switched sidebar variant' do
    lines = Array.new(90) { |i| "#{i.to_s.rjust(2, '0')} #{'a' * 60}" }
    doc = FakeDocument.new([Chapter.new(lines: lines, title: 'One')])
    service = build_service

    service.build_dynamic_map!(80, 24, doc,
                               config_reader: config_reader,
                               sidebar_visible: false)
    reader_state_reader.current_page_index = 1

    old_page = service.get_page(1)
    old_start = old_page[:start_line]
    reader_state_reader.sidebar_visible = true

    result = service.switch_dynamic_layout_variant!(
      80,
      24,
      doc,
      sidebar_visible: true,
      reader_state_reader: reader_state_reader
    )
    expect(result[:status]).to eq(:switched)
    idx = result.fetch(:current_page_index)
    switched_page = service.get_page(idx)
    expect(switched_page[:start_line]).to be <= old_start
    expect(switched_page[:end_line]).to be >= old_start
  end

  it 'hydrates cached compact pages against the active document when a document is provided' do
    doc = FakeDocument.new([Chapter.new(lines: ['many examples live here'], title: 'One')])
    service = build_service
    cached_pages = [
      {
        chapter_index: 0,
        page_in_chapter: 0,
        total_pages_in_chapter: 1,
        start_line: 0,
        end_line: 0,
      }
    ]

    service.hydrate_from_cache(cached_pages, width: 80, height: 24, doc: doc)
    hydrated = service.get_page(0, width: 80, height: 24)

    expect(hydrated[:lines]).not_to be_empty
  end
end
