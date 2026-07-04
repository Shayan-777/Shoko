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

  it 'styles links as colored text without underline by default' do
    styled = described_class.styled_segment('22', { link: '#note22' }, metadata: {})

    expect(styled).to start_with(described_class.color(:link))
    expect(styled).not_to include(Shoko::Shared::Terminal::Ansi::UNDERLINE)
  end

  it 'underlines hovered links' do
    styled = described_class.styled_segment('22', { link: '#note22', link_hover: true }, metadata: {})

    expect(styled).to start_with(described_class.color(:link))
    expect(styled).to include(Shoko::Shared::Terminal::Ansi::UNDERLINE)
  end

  it 'treats mostly-transparent book colors as absent instead of solid' do
    transparent_bg = described_class.styled_segment('x', { bg: 'rgba(0, 0, 0, 0)' }, metadata: {})
    expect(transparent_bg).not_to include("\e[48;5;")

    transparent_hex = described_class.styled_segment('x', { bg: '#00000000' }, metadata: {})
    expect(transparent_hex).not_to include("\e[48;5;")
  end

  it 'renders mostly-opaque rgba colors as their solid value' do
    styled = described_class.styled_segment('x', { fg: 'rgba(200, 40, 40, 0.9)', bg: '#222' }, metadata: {})

    expect(styled).to include("\e[38;5;")
    expect(styled).to include("\e[48;5;")
  end

  it 'drops a lone near-white or near-black background as unreadable' do
    lone_white = described_class.styled_segment('x', { bg: '#ffffff' }, metadata: {})
    expect(lone_white).not_to include("\e[48;5;")

    lone_black = described_class.styled_segment('x', { bg: 'black' }, metadata: {})
    expect(lone_black).not_to include("\e[48;5;")
  end

  it 'keeps an extreme background when the book pins the foreground too' do
    styled = described_class.styled_segment('x', { fg: '#333', bg: '#ffffff' }, metadata: {})

    expect(styled).to include("\e[38;5;")
    expect(styled).to include("\e[48;5;")
  end
end
