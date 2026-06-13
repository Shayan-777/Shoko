# frozen_string_literal: true

require 'spec_helper'
require 'shoko/core/models/document_anchor'

RSpec.describe Shoko::Core::Models::DocumentAnchor do
  describe '.from_h' do
    it 'builds from symbol keys' do
      anchor = described_class.from_h(quote: 'the fox', prefix: 'saw', suffix: 'jump', position: 0.25)

      expect(anchor.quote).to eq('the fox')
      expect(anchor.prefix).to eq('saw')
      expect(anchor.suffix).to eq('jump')
      expect(anchor.position).to eq(0.25)
    end

    it 'builds from string keys' do
      anchor = described_class.from_h('quote' => 'q', 'position' => '0.5')

      expect(anchor.quote).to eq('q')
      expect(anchor.position).to eq(0.5)
    end

    it 'returns nil for non-hash input' do
      expect(described_class.from_h(nil)).to be_nil
      expect(described_class.from_h('quote')).to be_nil
    end

    it 'normalizes blank strings to nil' do
      anchor = described_class.from_h(quote: '', prefix: nil, suffix: '  ', position: nil)

      expect(anchor.quote).to be_nil
      expect(anchor.prefix).to be_nil
      expect(anchor.suffix).to eq('  ')
      expect(anchor).not_to be_quote
    end

    it 'clamps position into 0..1 and drops garbage' do
      expect(described_class.from_h(position: 1.7).position).to eq(1.0)
      expect(described_class.from_h(position: -3).position).to eq(0.0)
      expect(described_class.from_h(position: 'garbage').position).to be_nil
    end
  end

  describe 'predicates' do
    it 'reports quote and position presence' do
      quote_anchor = described_class.from_h(quote: 'q')
      page_anchor = described_class.from_h(position: 0.4)
      empty_anchor = described_class.from_h({})

      expect(quote_anchor).to be_quote
      expect(quote_anchor).not_to be_empty
      expect(page_anchor).to be_position
      expect(page_anchor).not_to be_empty
      expect(empty_anchor).to be_empty
    end
  end

  describe '#to_h' do
    it 'round-trips through from_h' do
      anchor = described_class.from_h(quote: 'q', prefix: 'p', suffix: 's', position: 0.5)

      expect(described_class.from_h(anchor.to_h)).to eq(anchor)
    end
  end
end
