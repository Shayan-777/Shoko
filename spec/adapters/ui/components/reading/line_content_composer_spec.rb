# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Reading::LineContentComposer do
  # Build a mock config_reader that responds to port methods
  def build_config_reader(highlight_keywords: false, highlight_quotes: nil)
    Struct.new(:highlight_keywords, :highlight_quotes, keyword_init: true)
          .new(highlight_keywords: highlight_keywords, highlight_quotes: highlight_quotes)
  end

  let(:runtime_config) { Shoko::Adapters::Runtime::NullRuntimeConfig.instance }
  let(:composer) { described_class.new(runtime_config: runtime_config) }
  let(:render_style) { Shoko::Adapters::Ui::Components::RenderStyle }

  before do
    described_class.clear_compose_cache
  end

  it 'highlights keywords in plain lines when enabled' do
    config_reader = build_config_reader(highlight_keywords: true, highlight_quotes: false)

    plain, styled = composer.compose('fragrance', 40, config_reader)

    expect(plain).to eq('fragrance')
    expect(styled).to include(render_style.color(:accent))
  end

  it 'highlights quotes in plain lines when enabled' do
    config_reader = build_config_reader(highlight_quotes: true)

    plain, styled = composer.compose('He said "quote"', 40, config_reader)

    expect(plain).to eq('He said "quote"')
    expect(styled).to include(render_style.color(:quote))
    expect(styled).to include(Shoko::Shared::Terminal::Ansi::ITALIC)
  end

  it 'uses primary color for quote blocks when highlighting is disabled' do
    config_reader = build_config_reader(highlight_quotes: false)
    line = Shoko::Core::Models::DisplayLine.new(
      text: '"quote"',
      segments: [Shoko::Core::Models::TextSegment.new(text: '"quote"')],
      metadata: { block_type: :quote }
    )

    _plain, styled = composer.compose(line, 20, config_reader)

    expect(styled).to include(render_style.color(:primary))
    expect(styled).not_to include(render_style.color(:quote))
  end

  it 'treats legacy blockquote display lines as quote blocks' do
    config_reader = build_config_reader(highlight_quotes: true)
    line = Shoko::Core::Models::DisplayLine.new(
      text: '"legacy quote"',
      segments: [Shoko::Core::Models::TextSegment.new(text: '"legacy quote"')],
      metadata: { block_type: :blockquote }
    )

    _plain, styled = composer.compose(line, 30, config_reader)

    expect(styled).to include(render_style.color(:quote))
  end

  it 'adds accent styling for keywords in display lines' do
    config_reader = build_config_reader(highlight_keywords: true, highlight_quotes: false)
    line = Shoko::Core::Models::DisplayLine.new(
      text: 'fragrance',
      segments: [Shoko::Core::Models::TextSegment.new(text: 'fragrance')],
      metadata: {}
    )

    _plain, styled = composer.compose(line, 20, config_reader)

    expect(styled).to include(render_style.color(:accent))
  end

  it 'returns the same output with compose cache enabled and disabled' do
    config_reader = build_config_reader(highlight_keywords: true, highlight_quotes: true)
    line = Shoko::Core::Models::DisplayLine.new(
      text: 'He said "fragrance"',
      segments: [Shoko::Core::Models::TextSegment.new(text: 'He said "fragrance"')],
      metadata: {}
    )

    uncached = described_class.with_compose_cache(enabled: false) do
      described_class.clear_compose_cache
      composer.compose(line, 40, config_reader)
    end
    cached = described_class.with_compose_cache(enabled: true) do
      described_class.clear_compose_cache
      composer.compose(line, 40, config_reader)
    end

    expect(cached).to eq(uncached)
  end

  it 'reuses cached compose result objects when cache is enabled' do
    config_reader = build_config_reader(highlight_keywords: false, highlight_quotes: false)
    line = Shoko::Core::Models::DisplayLine.new(
      text: 'simple line',
      segments: [Shoko::Core::Models::TextSegment.new(text: 'simple line')],
      metadata: {}
    )

    first = described_class.with_compose_cache(enabled: true) do
      described_class.clear_compose_cache
      composer.compose(line, 30, config_reader)
    end
    second = described_class.with_compose_cache(enabled: true) do
      composer.compose(line, 30, config_reader)
    end

    expect(second.object_id).to eq(first.object_id)
  end

  it 'underlines only the hovered link span on a display line' do
    config_reader = build_config_reader(highlight_keywords: false, highlight_quotes: false)
    line = Shoko::Core::Models::DisplayLine.new(
      text: 'a22b',
      segments: [
        Shoko::Core::Models::TextSegment.new(text: 'a', styles: {}),
        Shoko::Core::Models::TextSegment.new(text: '22', styles: { link: '#note22' }),
        Shoko::Core::Models::TextSegment.new(text: 'b', styles: {}),
      ],
      metadata: {}
    )

    _plain, not_hovered = composer.compose(line, 20, config_reader, line_offset: 10, hovered_inline_link: nil)
    _plain, hovered = composer.compose(
      line,
      20,
      config_reader,
      line_offset: 10,
      hovered_inline_link: { line_offset: 10, start_char: 1, end_char: 3, href: '#note22' }
    )

    expect(not_hovered).not_to include(Shoko::Shared::Terminal::Ansi::UNDERLINE)
    expect(hovered).to include(Shoko::Shared::Terminal::Ansi::UNDERLINE)
  end
end
