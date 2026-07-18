# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::AsyncResultRelay do
  # Deterministic executor: collects jobs so the spec controls when the
  # "worker" runs them.
  let(:deferred_executor) do
    executor = Object.new
    executor.instance_variable_set(:@jobs, [])
    executor.define_singleton_method(:submit) { |&job| @jobs << job }
    executor.define_singleton_method(:run_all) { @jobs.shift.call until @jobs.empty? }
    executor
  end

  describe 'without an executor (synchronous mode)' do
    it 'runs the job inline and applies enqueued results immediately' do
      relay = described_class.new
      applied = []

      relay.submit { relay.enqueue { applied << :result } }

      expect(applied).to eq([:result])
      expect(relay.busy?).to be(false)
    end

    it 'propagates job errors to the caller like inline code did' do
      relay = described_class.new

      expect { relay.submit { raise Shoko::Error, 'inline boom' } }
        .to raise_error(Shoko::Error, 'inline boom')
    end
  end

  describe 'with an executor (asynchronous mode)' do
    it 'reports busy until the job ran and its results were drained' do
      relay = described_class.new(async_executor: deferred_executor)
      applied = []

      relay.submit { relay.enqueue { applied << :result } }

      expect(relay.busy?).to be(true)
      expect(applied).to be_empty

      deferred_executor.run_all
      expect(relay.busy?).to be(true) # results still queued

      expect(relay.drain!).to eq(1)
      expect(applied).to eq([:result])
      expect(relay.busy?).to be(false)
    end

    it 'drains results in submission order' do
      relay = described_class.new(async_executor: deferred_executor)
      applied = []

      relay.submit do
        relay.enqueue { applied << :first }
        relay.enqueue { applied << :second }
      end
      deferred_executor.run_all
      relay.drain!

      expect(applied).to eq(%i[first second])
    end

    it 'swallows submit failures and reports them via the return value' do
      stopped_executor = Object.new
      stopped_executor.define_singleton_method(:submit) { |&_job| raise StandardError, 'worker is shutting down' }
      relay = described_class.new(async_executor: stopped_executor)

      expect(relay.submit { :never_runs }).to be(false)
      expect(relay.busy?).to be(false)
    end

    it 'logs job errors as background noise without failing the submission' do
      logger = instance_double(Shoko::Application::Ports::Outbound::Logging)
      allow(logger).to receive(:debug)
      relay = described_class.new(async_executor: deferred_executor, logger: logger)

      expect(relay.submit { raise Shoko::Error, 'background boom' }).to be(true)
      deferred_executor.run_all

      expect(logger).to have_received(:debug)
        .with('async_result_relay.job_failed', error: 'Shoko::Error', message: 'background boom')
      expect(relay.busy?).to be(false)
    end

    it 'never double-decrements when an executor runs the block inline and then raises from submit' do
      # Job 1 stays queued on the deferred executor: pending count is 1.
      relay = described_class.new(async_executor: deferred_executor)
      relay.submit { relay.enqueue { nil } }
      expect(relay.busy?).to be(true)

      # Job 2 goes to an executor that RUNS the block (its ensure fires) and
      # then raises out of #submit. Without a once-only finisher the rescue
      # path would decrement again, consuming job 1's pending count.
      treacherous_executor = Object.new
      treacherous_executor.define_singleton_method(:submit) do |&job|
        job.call
        raise StandardError, 'submit exploded after running the job'
      end
      allow(relay).to receive(:resolve_executor).and_return(treacherous_executor)

      expect(relay.submit { :ran_inline }).to be(false)

      expect(relay.busy?).to be(true), 'job 1 is still queued; its pending count must survive'
      deferred_executor.run_all
      relay.drain!
      expect(relay.busy?).to be(false)
    end

    it 'treats a synchronous executor job error identically: submitted, logged, not a submit failure' do
      synchronous_executor = Object.new
      synchronous_executor.define_singleton_method(:submit) { |&job| job.call }
      logger = instance_double(Shoko::Application::Ports::Outbound::Logging)
      allow(logger).to receive(:debug)
      relay = described_class.new(async_executor: synchronous_executor, logger: logger)

      expect(relay.submit { raise Shoko::Error, 'sync boom' }).to be(true)

      expect(logger).to have_received(:debug)
        .with('async_result_relay.job_failed', error: 'Shoko::Error', message: 'sync boom')
      expect(logger).not_to have_received(:debug)
        .with('async_result_relay.submit_failed', anything)
      expect(relay.busy?).to be(false)
    end
  end

  it 'builds its executor lazily from the factory on first submit' do
    built = 0
    factory = lambda do
      built += 1
      deferred_executor
    end
    relay = described_class.new(executor_factory: factory)

    expect(built).to eq(0)
    relay.submit { relay.enqueue { nil } }
    relay.submit { relay.enqueue { nil } }

    expect(built).to eq(1)
    deferred_executor.run_all
    expect(relay.drain!).to eq(2)
  end
end
