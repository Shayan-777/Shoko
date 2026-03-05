# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe Shoko::Adapters::Storage::BackgroundWorker do
  def build_recording_logger
    events = []
    mutex = Mutex.new

    Object.new.tap do |logger|
      logger.define_singleton_method(:error) do |message, **metadata|
        mutex.synchronize { events << { level: :error, message: message, metadata: metadata } }
      end
      logger.define_singleton_method(:warn) do |message, **metadata|
        mutex.synchronize { events << { level: :warn, message: message, metadata: metadata } }
      end
      logger.define_singleton_method(:info) do |message, **metadata|
        mutex.synchronize { events << { level: :info, message: message, metadata: metadata } }
      end
      logger.define_singleton_method(:snapshot) do
        mutex.synchronize { events.dup }
      end
    end
  end

  def wait_until(timeout: 2.0, interval: 0.01)
    Timeout.timeout(timeout) do
      sleep interval until yield
    end
  end

  it 'restarts dead worker threads on submit and executes subsequent jobs' do
    logger = build_recording_logger
    worker = described_class.new(logger: logger, name: 'test-worker')
    executed = Queue.new

    worker.submit { raise 'boom' }

    wait_until do
      logger.snapshot.any? do |event|
        event[:message] == 'Background worker thread terminated unexpectedly' &&
          event[:metadata][:error_class] == 'RuntimeError'
      end
    end

    worker.submit { executed << :ok }

    wait_until { !executed.empty? }
    expect(executed.pop).to eq(:ok)
    expect(logger.snapshot).to include(
      hash_including(level: :warn, message: 'Background worker thread was not alive; restarting')
    )
  ensure
    worker&.shutdown
  end

  it 'raises WorkerStoppedError when submitting after shutdown' do
    logger = build_recording_logger
    worker = described_class.new(logger: logger, name: 'test-worker')
    worker.shutdown

    expect do
      worker.submit { :nope }
    end.to raise_error(described_class::WorkerStoppedError, 'worker is shutting down')
  end

  it 'logs termination, restart, and shutdown exit events' do
    logger = build_recording_logger
    worker = described_class.new(logger: logger, name: 'test-worker')

    worker.submit { raise 'thread-failure' }

    wait_until do
      logger.snapshot.any? do |event|
        event[:message] == 'Background worker thread terminated unexpectedly' &&
          event[:metadata][:error] == 'thread-failure'
      end
    end

    worker.submit { :ok }

    wait_until do
      logger.snapshot.any? do |event|
        event[:message] == 'Background worker thread was not alive; restarting'
      end
    end

    worker.shutdown

    wait_until do
      logger.snapshot.any? do |event|
        event[:message] == 'Background worker thread exited' &&
          event[:metadata][:reason] == 'shutdown'
      end
    end
  end
end
