# frozen_string_literal: true

require 'spec_helper'
require 'shoko/adapters/ui/components/status_bar/bar_composer'
require 'shoko/shared/terminal/text_metrics'

RSpec.describe Shoko::Adapters::Ui::Components::StatusBar::BarComposer do
  def visible_width(text)
    Shoko::Shared::Terminal::TextMetrics.visible_length(text)
  end

  def measured(text)
    { text: text, width: visible_width(text) }
  end

  it 'produces a line that fills the full width' do
    line = described_class.compose(width: 40, left: measured('left'), right: measured('right'))
    expect(visible_width(line)).to eq(40)
  end

  it 'keeps the right cluster and truncates the left with an ellipsis when space is tight' do
    long_title = 'A Very Long Book Title That Cannot Possibly Fit Here'
    line = described_class.compose(width: 24, left: measured(long_title), right: measured('42 / 318'))

    expect(visible_width(line)).to eq(24)
    expect(line).to include(described_class::ELLIPSIS)
    expect(line).to include('42 / 318')
  end

  it 'returns an empty string for non-positive widths' do
    expect(described_class.compose(width: 0, left: measured('x'), right: measured('y'))).to eq('')
  end
end
