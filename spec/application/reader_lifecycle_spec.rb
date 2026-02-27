# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::ReaderLifecycle do
  let(:controller) { instance_double('ReaderController') }
  let(:terminal_service) { instance_double('TerminalService') }
  let(:logger) { instance_double('Logger') }

  it 'reuses async executor when it already behaves like a background worker' do
    executor = instance_double('WorkerExecutor', submit: nil, shutdown: nil)
    lifecycle = described_class.new(
      controller,
      terminal_service: terminal_service,
      async_executor: executor
    )

    expect(lifecycle.ensure_background_worker).to be(executor)
  end

  it 'builds background worker with logger and upgrades inline async executor' do
    inline_executor = Shoko::Core::Services::InlineExecutor.new
    worker = instance_double('BackgroundWorker')
    logger_double = logger
    factory = lambda do |logger:, name:|
      expect(logger).to be(logger_double)
      expect(name).to eq('reader-background')
      worker
    end

    lifecycle = described_class.new(
      controller,
      terminal_service: terminal_service,
      background_worker_factory: factory,
      async_executor: inline_executor,
      logger: logger
    )

    expect(lifecycle.ensure_background_worker).to be(worker)
    expect(lifecycle.instance_variable_get(:@async_executor)).to be(worker)
  end

  it 'supports name-only worker factory signature for backward compatibility' do
    worker = instance_double('BackgroundWorker')
    factory = lambda do |name:|
      expect(name).to eq('reader-background')
      worker
    end

    lifecycle = described_class.new(
      controller,
      terminal_service: terminal_service,
      background_worker_factory: factory
    )

    expect(lifecycle.ensure_background_worker).to be(worker)
  end
end
