# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::Terminal::TextMetrics::Truncator do
  let(:controls) do
    instance_double(Shoko::Shared::Terminal::TextMetrics::RuntimeControls,
                    ascii_fast_path_enabled?: false,
                    visible_length_cache_enabled?: false)
  end
  let(:cache) { Shoko::Shared::Terminal::TextMetrics::VisibleLengthCache.new(controls: controls) }
  let(:measurer) { Shoko::Shared::Terminal::TextMetrics::Measurer.new(controls: controls, cache: cache) }

  subject(:truncator) { described_class.new(measurer: measurer) }

  it 'truncates to the visible width while preserving ANSI sequences' do
    expect(truncator.truncate_to("\e[1mabcdef\e[0m", 3)).to eq("\e[1mabc")
  end

  it 'passes through strings that already fit' do
    expect(truncator.truncate_to('abc', 5)).to eq('abc')
  end

  it 'expands tabs against the start column while truncating' do
    expect(truncator.truncate_to("\tx", 6, start_column: 2)).to eq('  x')
  end

  it 'pads left, right, and center to the exact width' do
    expect(truncator.pad_right('ab', 4)).to eq('ab  ')
    expect(truncator.pad_left('ab', 4)).to eq('  ab')
    expect(truncator.pad_center('ab', 6)).to eq('  ab  ')
  end

  it 'uses the byte fast path only when enabled and applicable' do
    allow(controls).to receive(:ascii_fast_path_enabled?).and_return(true)
    expect(truncator.truncate_to('abcdef', 3)).to eq('abc')
  end
end
