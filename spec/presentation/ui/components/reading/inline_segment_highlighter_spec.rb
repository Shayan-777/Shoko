# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Presentation::Ui::Components::Reading::InlineSegmentHighlighter do
  let(:text_segment) { Shoko::Core::Models::TextSegment }

  it 'applies quote and keyword styles to matching ranges' do
    segments = [
      text_segment.new(text: 'He said '),
      text_segment.new(text: '"fragrance"'),
    ]

    result = described_class.apply(
      segments,
      block_type: :paragraph,
      highlight_quotes: true,
      highlight_keywords: true
    )

    expect(result.map(&:text).join).to eq('He said "fragrance"')
    expect(result.any? { |segment| segment.styles[:quote] }).to be(true)
    expect(result.any? { |segment| segment.styles[:accent] }).to be(true)
  end

  it 'skips highlighting for code blocks' do
    segments = [text_segment.new(text: 'fragrance')]

    result = described_class.apply(
      segments,
      block_type: :code,
      highlight_quotes: true,
      highlight_keywords: true
    )

    expect(result).to be(segments)
  end
end
