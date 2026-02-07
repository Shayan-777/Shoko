# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::LayoutService do
  subject(:service) { described_class.new }

  it 'calculates metrics for split view' do
    width, height = service.calculate_metrics(120, 40, :split)
    expect(width).to be >= described_class::MIN_COLUMN_WIDTH
    expect(height).to eq(40 - described_class::CONTENT_VERTICAL_PADDING)
  end

  it 'adjusts height for relaxed line spacing' do
    expect(service.adjust_for_line_spacing(10, :relaxed)).to eq(5)
  end

  it 'calculates centered padding without going negative' do
    expect(service.calculate_centered_padding(40, 20)).to eq(10)
    expect(service.calculate_centered_padding(10, 20)).to eq(0)
  end
end
