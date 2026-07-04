# frozen_string_literal: true

require 'spec_helper'
require 'shoko/shared/terminal/color_depth'

RSpec.describe Shoko::Shared::Terminal::ColorDepth do
  it 'detects truecolor from COLORTERM' do
    expect(described_class.truecolor?(env: { 'COLORTERM' => 'truecolor' })).to be(true)
    expect(described_class.truecolor?(env: { 'COLORTERM' => '24bit' })).to be(true)
    expect(described_class.truecolor?(env: {})).to be(false)
  end

  it 'detects known truecolor terminals from TERM' do
    expect(described_class.truecolor?(env: { 'TERM' => 'xterm-kitty' })).to be(true)
    expect(described_class.truecolor?(env: { 'TERM' => 'xterm-256color' })).to be(false)
  end

  it 'honors the SHOKO_TRUECOLOR override in both directions' do
    expect(described_class.truecolor?(env: { 'SHOKO_TRUECOLOR' => '0', 'COLORTERM' => 'truecolor' })).to be(false)
    expect(described_class.truecolor?(env: { 'SHOKO_TRUECOLOR' => '1' })).to be(true)
  end
end
