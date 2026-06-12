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

  Chapter = Struct.new(:lines, :title)

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
    attr_accessor :current_page_index, :current_chapter

    def initialize(current_page_index:, current_chapter:)
      @current_page_index = current_page_index
      @current_chapter = current_chapter
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
    MutableReaderState.new(current_page_index: 0, current_chapter: 0)
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
      },
    ]

    service.hydrate_from_cache(cached_pages, width: 80, height: 24, doc: doc)
    hydrated = service.get_page(0, width: 80, height: 24)

    expect(hydrated[:lines]).not_to be_empty
  end
end
