# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::EventBus do
  let(:null_logger) { Shoko::Core::Services::NullLogger.new }

  it 'delivers emitted events to subscribers' do
    bus = described_class.new(logger: null_logger)
    subscriber = double('Subscriber')
    allow(subscriber).to receive(:handle_event)

    bus.subscribe(subscriber, :test_event)
    bus.emit_event(:test_event, foo: 'bar')

    expect(subscriber).to have_received(:handle_event).once
  end

  it 're-raises subscriber errors' do
    bus = described_class.new(logger: null_logger)
    subscriber = double('Subscriber', handle_event: nil)
    allow(subscriber).to receive(:handle_event).and_raise(StandardError, 'boom')
    bus.subscribe(subscriber, :boom)

    expect { bus.emit_event(:boom) }.to raise_error(StandardError, 'boom')
  end
end
