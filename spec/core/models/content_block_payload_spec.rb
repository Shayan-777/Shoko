# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Shoko::Core::Models::ContentBlockPayload do
  def block(**overrides)
    Shoko::Core::Models::ContentBlock.new(
      **{
        type: :heading,
        segments: [Shoko::Core::Models::TextSegment.new(text: 'Title', styles: { bold: true })],
        level: 2,
        metadata: { marker: '1.' },
      }.merge(overrides)
    )
  end

  # Blocks reach the JSON article cache and the frozen state tree, and JSON
  # turns every Symbol into a String on the way back.
  it 'round-trips a block through JSON without loss' do
    payload = JSON.parse(JSON.generate(described_class.dump([block])))

    restored = described_class.load(payload).first

    expect(restored.type).to eq(:heading)
    expect(restored.level).to eq(2)
    expect(restored.text).to eq('Title')
    expect(restored.segments.first.styles).to eq({ bold: true })
    expect(restored.metadata).to eq({ marker: '1.' })
  end

  it 'produces only plain JSON-safe data' do
    payload = described_class.dump([block])

    expect { JSON.generate(payload) }.not_to raise_error
    expect(payload.first[:type]).to be_a(String)
    expect(payload.first[:segments].first[:styles].keys).to all(be_a(String))
  end

  it 'is admissible into the frozen state tree' do
    expect { Shoko::Shared::DeepStructure.admit(described_class.dump([block])) }.not_to raise_error
  end

  it 'canonicalizes block-type aliases' do
    restored = described_class.load(described_class.dump([block(type: :blockquote)])).first

    expect(restored.type).to eq(:quote)
  end

  it 'keeps a textless structural block' do
    restored = described_class.load(described_class.dump([block(type: :rule, segments: [])])).first

    expect(restored.type).to eq(:rule)
    expect(restored.segments).to eq([])
  end

  it 'treats nil and empty input as no blocks' do
    expect(described_class.dump(nil)).to eq([])
    expect(described_class.load(nil)).to eq([])
  end

  it 'skips entries that are not block payloads' do
    expect(described_class.load(['nonsense', nil])).to eq([])
  end
end
