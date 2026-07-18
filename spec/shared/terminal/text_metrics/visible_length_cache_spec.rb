# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::Terminal::TextMetrics::VisibleLengthCache do
  let(:enabled) { true }
  let(:controls) do
    instance_double(Shoko::Shared::Terminal::TextMetrics::RuntimeControls,
                    visible_length_cache_enabled?: enabled)
  end

  subject(:cache) { described_class.new(controls: controls) }

  before { cache.clear! }
  after { cache.clear! }

  it 'computes on miss and serves the memo on hit' do
    computes = 0
    2.times { cache.fetch('abc') { computes += 1; 3 } }

    expect(computes).to eq(1)
    expect(cache.fetch('abc') { raise 'must not compute' }).to eq(3)
  end

  it 'bypasses the store when disabled' do
    allow(controls).to receive(:visible_length_cache_enabled?).and_return(false)
    computes = 0
    2.times { cache.fetch('abc') { computes += 1; 3 } }

    expect(computes).to eq(2)
  end

  it 'does not cache oversized inputs' do
    big = 'a' * (described_class::CACHEABLE_BYTES + 1)
    computes = 0
    2.times { cache.fetch(big) { computes += 1; 1 } }

    expect(computes).to eq(2)
  end

  it 'clear! empties the per-thread store' do
    cache.fetch('abc') { 3 }
    cache.clear!
    computes = 0
    cache.fetch('abc') { computes += 1; 3 }

    expect(computes).to eq(1)
  end
end
