# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::RenderStyle do
  it 'uses quote color when highlighting is enabled' do
    styled = described_class.styled_segment('quote', { quote: true }, metadata: { block_type: :quote, highlight_enabled: true })
    expect(styled).to start_with(described_class.color(:quote))
  end

  it 'falls back to primary color when highlighting is disabled' do
    styled = described_class.styled_segment('quote', { quote: true }, metadata: { block_type: :quote, highlight_enabled: false })
    expect(styled).to start_with(described_class.color(:primary))
  end

  it 'treats legacy blockquote metadata as quote styling' do
    styled = described_class.styled_segment('legacy', {}, metadata: { block_type: :blockquote, highlight_enabled: true })
    expect(styled).to start_with(described_class.color(:quote))
  end

  it 'uses accent color for keyword segments' do
    styled = described_class.styled_segment('word', { accent: true }, metadata: {})
    expect(styled).to start_with(described_class.color(:accent))
  end

  it 'applies underline and strikethrough ANSI styles when segment styles request them' do
    styled = described_class.styled_segment('text', { underline: true, strikethrough: true }, metadata: {})

    expect(styled).to include(Shoko::Shared::Terminal::Ansi::UNDERLINE)
    expect(styled).to include(Shoko::Shared::Terminal::Ansi::STRIKETHROUGH)
  end

  it 'renders superscript and subscript styles with transformed glyphs' do
    super_text = described_class.styled_segment('x2', { superscript: true }, metadata: {})
    sub_text = described_class.styled_segment('H2O', { subscript: true }, metadata: {})

    expect(super_text).to include('²')
    expect(sub_text).to include('₂')
  end
end
