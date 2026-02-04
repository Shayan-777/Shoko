# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::UI::AnnotationMarkup do
  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, '')
  end

  it 'keeps markers and applies strikethrough' do
    styler = described_class::Styler.new('-this-')
    styled = styler.render_lines(80).first

    expect(strip_ansi(styled)).to eq('this')
    expect(styled).to include(described_class::STYLE_ON[:strike])
  end

  it 'applies bold markers' do
    styler = described_class::Styler.new('*bold*')
    styled = styler.render_lines(80).first

    expect(strip_ansi(styled)).to eq('bold')
    expect(styled).to include(described_class::STYLE_ON[:bold])
  end

  it 'does not parse nested markers inside code' do
    styler = described_class::Styler.new('=code *x*=')
    styled = styler.render_lines(80).first

    expect(strip_ansi(styled)).to eq('code *x*')
    expect(styled).to include(described_class::STYLE_ON[:code])
    expect(styled).not_to include(described_class::STYLE_ON[:bold])
  end

  it 'carries styles across lines' do
    styler = described_class::Styler.new("*bold\ntext*")
    styled_lines = styler.render_lines(80)

    expect(strip_ansi(styled_lines.join("\n"))).to eq("bold\ntext")
    expect(styled_lines[0]).to include(described_class::STYLE_ON[:bold])
  end

  it 'allows escaping markers' do
    styler = described_class::Styler.new('\\*literal*')
    styled = styler.render_lines(80).first

    expect(strip_ansi(styled)).to eq('*literal*')
    expect(styled).not_to include(described_class::STYLE_ON[:bold])
  end

  it 'keeps unmatched markers visible and unstyled' do
    styler = described_class::Styler.new('-open only')
    styled = styler.render_lines(80).first

    expect(strip_ansi(styled)).to eq('-open only')
    expect(styled).not_to include(described_class::STYLE_ON[:strike])
  end

  it 'moves cursor left and right by visible characters' do
    styler = described_class::Styler.new('ab')
    width = 10

    expect(styler.move_right(0, width)).to eq(1)
    expect(styler.move_left(1, width)).to eq(0)
  end

  it 'moves cursor up and down across lines' do
    styler = described_class::Styler.new("ab\ncd")
    width = 10

    expect(styler.move_down(1, width)).to eq(4)
    expect(styler.move_up(4, width)).to eq(1)
  end
end
