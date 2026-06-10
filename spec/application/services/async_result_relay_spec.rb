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
