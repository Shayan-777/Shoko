# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::LifecycleRunner do
  let(:controller) { instance_double(Shoko::Adapters::Input::Controllers::ReaderController) }
  let(:terminal_session) { instance_double(Shoko::Application::Ports::Outbound::TerminalSession) }
  let(:logger) { instance_double(Shoko::Application::Ports::Outbound::Logging) }
  let(:background_worker_builder_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder

      def initialize(worker:, logger_expectation: nil)
        @worker = worker
        @logger_expectation = logger_expectation
      end

      def build(name:, logger:)
        raise 'unexpected logger' if @logger_expectation && @logger_expectation != logger
        raise 'unexpected name' unless name == 'reader-background'

        @worker
      end
    end
  end

  it 'reuses async executor when it already behaves like a background worker' do
    executor = Class.new do
      include Shoko::Application::Ports::Outbound::AsyncExecutor

      def submit(&block)
        block&.call
      end

      def shutdown(_timeout = nil)
        nil
      end
    end.new
    lifecycle = described_class.new(
      controller,
      terminal_session: terminal_session,
      async_executor: executor
    )

    expect(lifecycle.ensure_background_worker).to be(executor)
  end

  it 'builds background worker with logger and upgrades inline async executor' do
    inline_executor = Shoko::Adapters::Runtime::InlineExecutorAdapter.new
    worker = instance_double(Shoko::Adapters::Storage::BackgroundWorker)
    builder = background_worker_builder_class.new(worker: worker, logger_expectation: logger)

    lifecycle = described_class.new(
      controller,
      terminal_session: terminal_session,
      background_worker_builder: builder,
      async_executor: inline_executor,
      logger: logger
    )

    expect(lifecycle.ensure_background_worker).to be(worker)
    expect(lifecycle.instance_variable_get(:@async_executor)).to be(worker)
  end

  it 'raises when no builder is configured and async executor is not reusable' do
    lifecycle = described_class.new(
      controller,
      terminal_session: terminal_session
    )

    expect { lifecycle.ensure_background_worker }
      .to raise_error(Shoko::ConfigurationError, /background_worker_builder/)
  end
end
