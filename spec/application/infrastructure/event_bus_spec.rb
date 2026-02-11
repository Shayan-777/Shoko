# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::State::EventBus do
  let(:null_logger) { Shoko::Core::Services::NullLogger.new }

  it 'delivers emitted events to subscribers' do
    bus = described_class.new(logger: null_logger)
    subscriber = double('Subscriber')
    allow(subscriber).to receive(:handle_event)

    bus.subscribe(subscriber, :test_event)
    bus.emit_event(:test_event, foo: 'bar')

    expect(subscriber).to have_received(:handle_event).once
  end

  it 'suppresses subscriber errors when requested' do
    bus = described_class.new(logger: null_logger)
    subscriber = double('Subscriber', handle_event: nil)
    allow(subscriber).to receive(:handle_event).and_raise(StandardError, 'boom')
    bus.subscribe(subscriber, :boom)

    expect { bus.emit_event(:boom) }.not_to raise_error
  end

  it 'can be configured to re-raise subscriber errors' do
    bus = described_class.new(logger: null_logger, raise_subscriber_errors: true)
    subscriber = double('Subscriber', handle_event: nil)
    allow(subscriber).to receive(:handle_event).and_raise(StandardError, 'boom')
    bus.subscribe(subscriber, :boom)

    expect { bus.emit_event(:boom) }.to raise_error(StandardError, 'boom')
  end
end
