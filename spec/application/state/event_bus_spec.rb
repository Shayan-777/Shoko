# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::State::EventBus do
  let(:null_logger) { Shoko::Core::Services::NullLogger.new }

  it 'delivers emitted events to subscribers' do
    bus = described_class.new(logger: null_logger)
    subscriber = double('Subscriber')
    allow(subscriber).to receive(:handle_event)

    bus.subscribe(subscriber, :test_event)
    bus.emit_event(:test_event, foo: 'bar')

    expect(subscriber).to have_received(:handle_event).once
  end

  it 'isolates subscriber errors: logs them, keeps emitting, notifies remaining subscribers' do
    logger = double('Logger', error: nil)
    bus = described_class.new(logger: logger)
    failing = double('FailingSubscriber')
    allow(failing).to receive(:handle_event).and_raise(NoMethodError, 'boom')
    healthy = double('HealthySubscriber')
    allow(healthy).to receive(:handle_event)
    bus.subscribe(failing, :boom)
    bus.subscribe(healthy, :boom)

    expect { bus.emit_event(:boom) }.not_to raise_error

    expect(healthy).to have_received(:handle_event).once
    expect(logger).to have_received(:error).with(
      'Event subscriber error',
      hash_including(event_type: :boom, error_class: 'NoMethodError', error: 'boom')
    )
  end
end
