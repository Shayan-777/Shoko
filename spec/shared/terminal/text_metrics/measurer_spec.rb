# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::Terminal::TextMetrics::Measurer do
  let(:controls) do
    instance_double(Shoko::Shared::Terminal::TextMetrics::RuntimeControls, ascii_fast_path_enabled?: true)
  end
  let(:cache) { Shoko::Shared::Terminal::TextMetrics::VisibleLengthCache.new(controls: cache_controls) }
  let(:cache_controls) do
    instance_double(Shoko::Shared::Terminal::TextMetrics::RuntimeControls, visible_length_cache_enabled?: false)
  end

  subject(:measurer) { described_class.new(controls: controls, cache: cache) }

  it 'measures visible width across ANSI, tabs, and wide characters' do
    expect(measurer.visible_length("\e[1mhi\e[0m")).to eq(2)
    expect(measurer.visible_length("a\tb")).to eq(5)
    expect(measurer.visible_length('héllo')).to eq(5)
  end

  it 'expands tabs against the running column' do
    expect(measurer.expand_tabs("ab\tc")).to eq('ab  c')
  end

  it 'treats soft hyphens as zero-width' do
    expect(measurer.display_width_for("­")).to eq(0)
  end

  it 'builds cell geometry with char offsets and screen positions' do
    cells = measurer.cell_data_for('ab')
    expect(cells.map { |c| c[:screen_x] }).to eq([0, 1])
    expect(cells.last).to include(char_start: 1, char_end: 2, display_width: 1)
  end

  it 'classifies fast-ASCII candidates strictly' do
    expect(measurer.fast_ascii_candidate?('plain')).to be(true)
    expect(measurer.fast_ascii_candidate?("with\ttab")).to be(false)
    expect(measurer.fast_ascii_candidate?("esc\e[0m")).to be(false)
    expect(measurer.fast_ascii_candidate?('héllo')).to be(false)
  end
end
