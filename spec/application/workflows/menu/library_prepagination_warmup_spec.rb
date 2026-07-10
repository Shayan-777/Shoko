# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::LibraryPrepaginationWarmup do
  # Runs the submitted block synchronously so the batch can be asserted inline.
  let(:worker) do
    Class.new do
      def submit(&block)
        block.call
        self
      end

      def shutdown(*); end
    end.new
  end

  let(:background_worker_builder) do
    Class.new do
      include Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder

      def initialize(worker)
        @worker = worker
      end

      def build(name:, logger:)
        @worker
      end
    end.new(worker)
  end

  # Scripted batch runner: replays the given events to on_event and returns
  # the given status, recording how it was invoked.
  let(:batch_events) do
    [
      { event: 'start', total: 2, paths: ['/books/a.epub', '/books/b.epub'] },
      { event: 'report', done: 1 },
      { event: 'report', done: 2 },
      { event: 'finish' },
    ]
  end
  let(:batch_status) { :completed }
  let(:batch_runner) do
    Class.new do
      include Shoko::Application::Ports::Outbound::PrepaginationBatchRunner

      attr_reader :calls, :cancelled, :reset_count

      def initialize(events, status)
        @events = events
        @status = status
        @calls = []
        @cancelled = false
        @reset_count = 0
      end

      def run_batch(width:, height:, on_event:)
        @calls << [width, height]
        @events.each { |event| on_event.call(event) }
        @status
      end

      def cancel_batch
        @cancelled = true
      end

      def reset_cancellation
        @reset_count += 1
        @cancelled = false
      end
    end.new(batch_events, batch_status)
  end

  let(:runtime_context) do
    Class.new do
      include Shoko::Application::Ports::Outbound::ReaderRuntimeContext

      def terminal_size
        Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 100, height: 40)
      end
    end.new
  end

  let(:progress_writer) do
    Class.new do
      include Shoko::Application::Ports::Outbound::PrepaginationProgressWriter

      attr_reader :events

      def initialize
        @events = []
      end

      def start(total:, paths:)
        @events << [:start, total, paths]
      end

      def report(done:)
        @events << [:report, done]
      end

      def finish
        @events << [:finish]
      end
    end.new
  end
  let(:logger) { instance_double(Shoko::Application::Ports::Outbound::Logging, debug: nil) }

  let(:config) do
    Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(
      prepaginate_on_resize: prepaginate_on_resize,
      last_paginated_size: last_paginated_size,
      page_numbering_mode: :dynamic
    )
  end
  let(:prepaginate_on_resize) { true }
  let(:last_paginated_size) { nil }

  let(:app_config_store) do
    store_config = config
    Class.new do
      def initialize(config)
        @config = config
      end

      def load
        @config
      end

      def save(config)
        @config = config
      end
    end.new(store_config)
  end

  subject(:warmup) do
    described_class.new(
      deps: described_class::Dependencies.new(
        batch_runner: batch_runner,
        app_config_store: app_config_store,
        reader_runtime_context: runtime_context,
        progress_writer: progress_writer,
        background_worker_builder: background_worker_builder,
        logger: logger
      )
    )
  end

  context 'when the setting is off' do
    let(:prepaginate_on_resize) { false }

    it 'does nothing' do
      expect(warmup.start).to eq(:disabled)
      expect(batch_runner.calls).to be_empty
    end
  end

  context 'when the library was already paginated at the current size' do
    let(:last_paginated_size) { '100x40' }

    it 'skips the batch' do
      expect(warmup.start).to eq(:unchanged)
      expect(batch_runner.calls).to be_empty
      expect(progress_writer.events).to be_empty
    end
  end

  context 'when enabled and the size changed' do
    it 'runs the batch at the current size and mirrors its progress' do
      expect(warmup.start).to eq(:started)

      expect(batch_runner.calls).to eq([[100, 40]])
      expect(progress_writer.events).to eq(
        [[:start, 2, ['/books/a.epub', '/books/b.epub']], [:report, 1], [:report, 2], [:finish]]
      )
    end

    it 'records the size it paginated for so a later run is skipped' do
      warmup.start

      expect(app_config_store.load.last_paginated_size).to eq('100x40')
    end

    it 'reports :error instead of raising when the worker refuses the submit' do
      allow(worker).to receive(:submit)
        .and_raise(Shoko::Adapters::Storage::BackgroundWorker::WorkerStoppedError, 'worker is shutting down')

      expect(warmup.start).to eq(:error)
      expect(batch_runner.calls).to be_empty
    end
  end

  context 'when the batch child fails' do
    let(:batch_status) { :failed }

    it 'keeps the old signature so the next menu start retries' do
      warmup.start

      expect(app_config_store.load.last_paginated_size).to be_nil
    end

    it 'still finishes the progress feedback' do
      warmup.start

      expect(progress_writer.events.last).to eq([:finish])
    end
  end

  context 'when the batch was cancelled mid-flight' do
    let(:batch_status) { :cancelled }

    it 'does not record the new signature' do
      warmup.start

      expect(app_config_store.load.last_paginated_size).to be_nil
    end
  end

  describe '#cancel' do
    it 'stops the batch child and shuts the worker down' do
      warmup.start
      expect(worker).to receive(:shutdown)

      warmup.cancel

      expect(batch_runner.cancelled).to be(true)
    end

    context 'when the batch was cancelled by a menu exit' do
      let(:batch_status) { :cancelled }

      it 'does not poison the next session: start re-arms the runner' do
        # The runner's cancel latch persists past the menu exit that set it;
        # without the start-time reset every later batch would be killed at
        # spawn for the life of the process.
        warmup.start
        warmup.cancel

        expect(warmup.start).to eq(:started)

        expect(batch_runner.reset_count).to eq(2)
        expect(batch_runner.cancelled).to be(false)
        expect(batch_runner.calls.length).to eq(2)
      end
    end
  end
end
