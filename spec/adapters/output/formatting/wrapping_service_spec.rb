# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::WrappingService do
  let(:text_metrics) { Shoko::Adapters::Output::Terminal::TextMetricsPortAdapter.new(runtime_config: runtime_config) }
  let(:async_executor) { Shoko::Adapters::Runtime::InlineExecutorAdapter.new }
  let(:runtime_config) { Shoko::Adapters::Output::Terminal::NullRuntimeConfig.instance }
  let(:chapter_cache_factory) do
    lambda do |text_metrics:|
      Shoko::Core::Services::Pagination::Internal::ChapterCache.new(
        text_metrics: text_metrics
      )
    end
  end
  let(:formatting_service) do
    Object.new.tap do |service|
      service.extend(Shoko::Application::Ports::Outbound::ChapterFormatter)
      service.define_singleton_method(:wrap_window) { |_doc, _chapter, _width, offset:, length:| [] }
      service.define_singleton_method(:wrap_all) { |_doc, _chapter, _width| [] }
      service.define_singleton_method(:ensure_formatted!) { |_doc, _chapter, _chapter_obj| nil }
    end
  end

  def build_service(text_metrics: self.text_metrics,
                    formatting_service: self.formatting_service,
                    chapter_cache_factory: self.chapter_cache_factory)
    described_class.new(
      text_metrics: text_metrics,
      async_executor: async_executor,
      runtime_config: runtime_config,
      formatting_service: formatting_service,
      chapter_cache_factory: chapter_cache_factory
    )
  end

  it 'does not reuse window cache across different line sets' do
    service = build_service

    lines_a = ['alpha beta']
    lines_b = ['gamma']

    wrapped_a = service.wrap_window(lines_a, 0, 5, 0, 2)
    wrapped_b = service.wrap_window(lines_b, 0, 5, 0, 2)

    expect(wrapped_a).not_to eq(wrapped_b)
    expect(wrapped_b).to eq(['gamma'])
  end

  it 'reuses cached windows for identical line sets' do
    service = build_service

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

    service = build_service(text_metrics: counting_metrics)

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

  it 'contains a prefetch submit refused by a stopping worker' do
    allow(async_executor).to receive(:submit)
      .and_raise(Shoko::Adapters::Storage::BackgroundWorker::WorkerStoppedError, 'worker is shutting down')

    formatting_service.define_singleton_method(:plain_lines_for) { |_doc, _chapter| [] }
    chapter = Struct.new(:lines).new(%w[alpha beta gamma delta])
    document = Object.new
    document.define_singleton_method(:get_chapter) { |_index| chapter }

    service = build_service
    visible = nil
    expect { visible = service.fetch_window_and_prefetch(document, 0, 80, 0, 2, 1) }.not_to raise_error

    expect(visible).to eq(%w[alpha beta])
    expect(async_executor).to have_received(:submit)
  end

  it 'uses explicitly provided document for formatted wrapping when container has no document' do
    formatting_service = Object.new
    formatting_service.extend(Shoko::Application::Ports::Outbound::ChapterFormatter)
    display_line_a = Shoko::Application::Ports::Outbound::Formatting::DisplayLine.new(text: 'Heading', segments: [], metadata: {})
    display_line_b = Shoko::Application::Ports::Outbound::Formatting::DisplayLine.new(text: 'Body', segments: [], metadata: {})
    document = double('Document')
    lines = ['fallback heading', 'fallback body']

    formatting_service.define_singleton_method(:wrap_window) do |_document, _chapter, _width, offset:, length:|
      [display_line_a, display_line_b]
    end
    formatting_service.define_singleton_method(:wrap_all) { |_doc, _chapter, _width| [] }
    formatting_service.define_singleton_method(:ensure_formatted!) { |_doc, _chapter, _chapter_obj| nil }

    service = build_service(formatting_service: formatting_service)

    wrapped = service.wrap_window(lines, 0, 20, 0, 2, document: document)
    expect(wrapped).to eq(%w[Heading Body])
  end

  it 'uses the injected chapter cache factory' do
    cache = instance_double('ChapterCache',
                            get_wrapped_lines: ['wrapped'],
                            clear_cache_for_width: nil)
    factory_calls = 0
    factory = lambda do |text_metrics:|
      factory_calls += 1
      expect(text_metrics).not_to be_nil
      cache
    end

    service = build_service(chapter_cache_factory: factory)

    expect(service.wrap_lines(['wrapped'], 0, 80)).to eq(['wrapped'])
    expect(factory_calls).to eq(1)

    service.clear_cache
    expect(factory_calls).to eq(2)
  end
end
