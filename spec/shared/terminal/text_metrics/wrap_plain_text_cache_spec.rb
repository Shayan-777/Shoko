# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::Terminal::TextMetrics::WrapPlainTextCache do
  let(:controls) do
    instance_double(Shoko::Shared::Terminal::TextMetrics::RuntimeControls,
                    wrap_plain_text_cache_enabled?: true)
  end

  subject(:cache) { described_class.new(controls: controls) }

  after { cache.clear! }

  it 'returns the frozen stored value on miss AND hit — one consistent contract' do
    first = cache.lookup('a b', 3) { ['a', 'b'] }
    second = cache.lookup('a b', 3) { raise 'must not compute' }

    expect(first).to be_frozen
    expect(first).to all(be_frozen)
    expect(second).to equal(first)
  end

  it 'keys by width and source independently' do
    cache.lookup('a b', 3) { ['3'] }
    expect(cache.lookup('a b', 5) { ['5'] }).to eq(['5'])
    expect(cache.lookup('a b', 3) { raise }).to eq(['3'])
  end

  it 'is genuinely LRU: a recent hit survives eviction over an older untouched entry' do
    stub_const("#{described_class}::LIMIT", 2)
    cache.lookup('old', 1) { ['old'] }
    cache.lookup('used', 1) { ['used'] }
    cache.lookup('old', 1) { raise } # hit refreshes recency of 'old'
    cache.lookup('new', 1) { ['new'] } # evicts 'used', the least recently used

    expect(cache.lookup('old', 1) { raise 'old was wrongly evicted' }).to eq(['old'])
    computes = 0
    cache.lookup('used', 1) { computes += 1; ['used'] }
    expect(computes).to eq(1)
  end
end
