# frozen_string_literal: true

require 'spec_helper'
require 'shoko/adapters/ui/components/status_bar/progress_bar'
require 'shoko/shared/terminal/text_metrics'

RSpec.describe Shoko::Adapters::Ui::Components::StatusBar::ProgressBar do
  def visible_width(text)
    Shoko::Shared::Terminal::TextMetrics.visible_length(text)
  end

  it 'always renders exactly the requested number of visible cells' do
    [0.0, 0.13, 0.5, 0.999, 1.0].each do |fraction|
      bar = described_class.render(fraction: fraction, cells: 12)
      expect(visible_width(bar)).to eq(12)
    end
  end

  it 'renders an empty groove at zero progress' do
    bar = described_class.render(fraction: 0.0, cells: 8)
    expect(bar).to include(described_class::GROOVE)
    expect(bar).not_to include(described_class::FULL)
  end

  it 'fills completely at full progress' do
    bar = described_class.render(fraction: 1.0, cells: 8)
    expect(bar).not_to include(described_class::GROOVE)
    expect(bar.scan(described_class::FULL).length).to eq(8)
  end

  it 'clamps out-of-range fractions' do
    expect(visible_width(described_class.render(fraction: -1.0, cells: 6))).to eq(6)
    expect(visible_width(described_class.render(fraction: 5.0, cells: 6))).to eq(6)
  end

  it 'returns an empty string for non-positive widths' do
    expect(described_class.render(fraction: 0.5, cells: 0)).to eq('')
  end
end
