# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::WrappingService do
  let(:text_metrics) { Shoko::Core::Services::DefaultTextMetrics.new }
  let(:async_executor) { Shoko::Core::Services::InlineExecutor.new }

  it 'does not reuse window cache across different line sets' do
    service = described_class.new(
      text_metrics: text_metrics,
      async_executor: async_executor
    )

    lines_a = ['alpha beta']
    lines_b = ['gamma']

    wrapped_a = service.wrap_window(lines_a, 0, 5, 0, 2)
    wrapped_b = service.wrap_window(lines_b, 0, 5, 0, 2)

    expect(wrapped_a).not_to eq(wrapped_b)
    expect(wrapped_b).to eq(['gamma'])
  end

  it 'reuses cached windows for identical line sets' do
    service = described_class.new(
      text_metrics: text_metrics,
      async_executor: async_executor
    )

    lines = ['alpha beta']
    first = service.wrap_window(lines, 0, 5, 0, 2)
    second = service.wrap_window(lines, 0, 5, 0, 2)

    expect(second).to eq(first)
  end

  it 'reuses covered ranges from prefetched windows without rewrapping' do
    original_env = ENV.fetch('SHOKO_DISABLE_WINDOW_RANGE_CACHE', nil)
    ENV['SHOKO_DISABLE_WINDOW_RANGE_CACHE'] = '0'

    call_count = 0
    counting_metrics = Object.new
    counting_metrics.define_singleton_method(:wrap_plain_text) do |line, _width|
      call_count += 1
      [line]
    end

    service = described_class.new(
      text_metrics: counting_metrics,
      async_executor: async_executor
    )

    lines = %w[alpha beta gamma delta epsilon]
    prefetched = service.wrap_window(lines, 0, 80, 0, 5)
    expect(prefetched).to eq(lines)

    calls_after_prefetch = call_count
    covered = service.wrap_window(lines, 0, 80, 2, 2)
    expect(covered).to eq(%w[gamma delta])
    expect(call_count).to eq(calls_after_prefetch)
  ensure
    if original_env.nil?
      ENV.delete('SHOKO_DISABLE_WINDOW_RANGE_CACHE')
    else
      ENV['SHOKO_DISABLE_WINDOW_RANGE_CACHE'] = original_env
    end
  end

  it 'uses explicitly provided document for formatted wrapping when container has no document' do
    formatting_service = double('FormattingService')
    display_line_a = Shoko::Core::Models::DisplayLine.new(text: 'Heading', segments: [], metadata: {})
    display_line_b = Shoko::Core::Models::DisplayLine.new(text: 'Body', segments: [], metadata: {})
    document = double('Document')
    lines = ['fallback heading', 'fallback body']

    expect(formatting_service).to receive(:wrap_window).with(
      document,
      0,
      20,
      offset: 0,
      length: 2
    ).and_return([display_line_a, display_line_b])

    service = described_class.new(
      text_metrics: text_metrics,
      async_executor: async_executor,
      formatting_service_provider: -> { formatting_service }
    )

    wrapped = service.wrap_window(lines, 0, 20, 0, 2, document: document)
    expect(wrapped).to eq(%w[Heading Body])
  end

  it 'uses the shared core chapter cache implementation' do
    service = described_class.new(
      text_metrics: text_metrics,
      async_executor: async_executor
    )

    cache = service.instance_variable_get(:@chapter_cache)
    expect(cache).to be_a(Shoko::Core::Services::Pagination::Internal::ChapterCache)
  end
end
