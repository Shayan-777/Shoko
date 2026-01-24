# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::Reading::LineContentComposer do
  # Build a mock config_reader that responds to port methods
  def build_config_reader(highlight_keywords: false, highlight_quotes: nil)
    Struct.new(:highlight_keywords, :highlight_quotes, keyword_init: true)
          .new(highlight_keywords: highlight_keywords, highlight_quotes: highlight_quotes)
  end

  let(:composer) { described_class.new }
  let(:render_style) { Shoko::Adapters::Output::Ui::Components::RenderStyle }

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
    expect(styled).to include(Shoko::Terminal::ANSI::ITALIC)
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
end
