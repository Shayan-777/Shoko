# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Events::DomainEventBus do
  let(:event_publisher) { instance_double('EventPublisher', publish_event: nil) }
  let(:logger) { instance_double('Logger', error: nil) }
  let(:event_bus) { described_class.new(event_publisher: event_publisher, logger: logger) }
  let(:bookmark) { Struct.new(:chapter_index, :line_offset).new(1, 5) }
  let(:event) { Shoko::Core::Events::BookmarkAdded.new(book_path: '/books/a.epub', bookmark: bookmark) }

  it 'publishes domain events through the EventPublisher port' do
    event_bus.publish(event)

    expect(event_publisher).to have_received(:publish_event).with(
      :BookmarkAdded,
      hash_including(event_data: hash_including(:event_id, :event_type, :occurred_at, :aggregate_id, :version, :data))
    )
  end

  it 'notifies subscribers for published event classes' do
    received = nil
    event_bus.subscribe(Shoko::Core::Events::BookmarkAdded) { |e| received = e }

    event_bus.publish(event)

    expect(received).to eq(event)
  end

  it 'rejects non-domain-event inputs' do
    expect { event_bus.publish(:bad) }.to raise_error(ArgumentError, /BaseDomainEvent/)
  end
end
