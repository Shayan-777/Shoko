# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::Terminal::TextMetrics::WrapPlainTextCache do
  let(:enabled) { true }
  let(:controls) do
    instance_double(Shoko::Shared::Terminal::TextMetrics::RuntimeControls,
                    wrap_plain_text_cache_enabled?: enabled)
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

  it 'keeps a copied frozen key after a hit when the caller source is mutable' do
    source = +'alpha'
    cache.lookup(source, 5) { ['alpha'] }
    cache.lookup(source, 5) { raise 'must hit' }

    stored_key = Thread.current[described_class::STORE_KEY].keys.first
    expect(stored_key).to be_frozen
    expect(stored_key.last).to be_frozen
    expect(stored_key.last).not_to equal(source)

    source.replace('omega')
    expect(cache.lookup('alpha', 5) { raise 'caller mutation corrupted the key' }).to eq(['alpha'])
    expect(Thread.current[described_class::STORE_KEY].length).to eq(1)
  end

  it 'returns immutable lines when caching is disabled or the source is too large' do
    allow(controls).to receive(:wrap_plain_text_cache_enabled?).and_return(false)
    disabled = cache.lookup('a b', 3) { [+'a', +'b'] }

    allow(controls).to receive(:wrap_plain_text_cache_enabled?).and_return(true)
    oversized_source = 'x' * (described_class::CACHEABLE_BYTES + 1)
    oversized = cache.lookup(oversized_source, 3) { [+'x'] }

    expect(disabled).to be_frozen
    expect(disabled).to all(be_frozen)
    expect(oversized).to be_frozen
    expect(oversized).to all(be_frozen)
  end
end
