# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Events::BaseDomainEvent do
  class TestDomainEvent < described_class
    required_attributes :value
    typed_attributes value: String
  end

  it 'requires injected event metadata' do
    expect do
      TestDomainEvent.new(value: 'x')
    end.to raise_error(ArgumentError, /missing keywords: :event_id, :occurred_at/)
  end

  it 'stores injected metadata and serializes it' do
    event = TestDomainEvent.new(
      event_id: 'evt-1',
      occurred_at: Time.utc(2024, 1, 1, 0, 0, 0),
      value: 'x'
    )

    expect(event.event_id).to eq('evt-1')
    expect(event.occurred_at).to eq(Time.utc(2024, 1, 1, 0, 0, 0))
    expect(event.to_h[:occurred_at]).to eq('2024-01-01T00:00:00Z')
  end
end
