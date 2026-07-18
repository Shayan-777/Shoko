# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::Terminal::TextMetrics::Wrapper do
  let(:controls) do
    instance_double(Shoko::Shared::Terminal::TextMetrics::RuntimeControls,
                    ascii_fast_path_enabled?: false,
                    visible_length_cache_enabled?: false,
                    wrap_plain_text_cache_enabled?: cache_enabled)
  end
  let(:cache_enabled) { false }
  let(:visible_cache) { Shoko::Shared::Terminal::TextMetrics::VisibleLengthCache.new(controls: controls) }
  let(:wrap_cache) { Shoko::Shared::Terminal::TextMetrics::WrapPlainTextCache.new(controls: controls) }
  let(:measurer) { Shoko::Shared::Terminal::TextMetrics::Measurer.new(controls: controls, cache: visible_cache) }

  subject(:wrapper) { described_class.new(measurer: measurer, cache: wrap_cache) }

  it 'word-wraps plain text to the width' do
    expect(wrapper.wrap_plain_text('aaa bbb ccc', 7)).to eq(['aaa bbb', 'ccc'])
  end

  it 'hard-wraps oversized words by cells and carries the tail' do
    expect(wrapper.wrap_plain_text('abcdefgh xy', 4)).to eq(%w[abcd efgh xy])
  end

  it 'wraps raw streams by grapheme cells, honoring newlines and tabs' do
    expect(wrapper.wrap_cells("ab\ncd", 10)).to eq(%w[ab cd])
    expect(wrapper.wrap_cells('abcdef', 3)).to eq(%w[abc def])
  end

  context 'with the wrap cache enabled' do
    let(:cache_enabled) { true }

    around do |example|
      example.run
    ensure
      wrap_cache.clear!
    end

    it 'memoizes by [width, source] and serves frozen lines from the cache' do
      wrapper.wrap_plain_text('aaa bbb', 3)
      second = wrapper.wrap_plain_text('aaa bbb', 3)
      third = wrapper.wrap_plain_text('aaa bbb', 3)

      expect(third).to equal(second)
      expect(second).to be_frozen
      expect(second).to all(be_frozen)
      expect(second).to eq(%w[aaa bbb])
    end
  end
end
