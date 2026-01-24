# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::FormattingService do
  it 'wraps chapter content into display lines' do
    blocks = [
      Shoko::Core::Models::ContentBlock.new(
        type: :paragraph,
        segments: [Shoko::Core::Models::TextSegment.new(text: 'Hello world')]
      ),
      Shoko::Core::Models::ContentBlock.new(
        type: :list_item,
        segments: [Shoko::Core::Models::TextSegment.new(text: 'Item one')],
        level: 1
      ),
      Shoko::Core::Models::ContentBlock.new(
        type: :code,
        segments: [Shoko::Core::Models::TextSegment.new(text: "code\nline")]
      ),
      Shoko::Core::Models::ContentBlock.new(type: :separator, segments: []),
      Shoko::Core::Models::ContentBlock.new(type: :break, segments: []),
    ]

    parser_factory = lambda do |_raw|
      Class.new do
        define_method(:parse) { blocks }
      end.new
    end

    service = described_class.new(xhtml_parser_factory: parser_factory)

    chapter = Struct.new(:raw_content, :lines, :blocks, :metadata).new(
      '<p>raw</p>',
      [],
      nil,
      { source_path: '/tmp/book.epub' }
    )
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.epub')

    allow(Shoko::Adapters::Output::Kitty::KittyGraphics).to receive(:supported?).and_return(false)

    lines = service.wrap_all(doc, 0, 20, config: double('Config', get: false), lines_per_page: 10)
    expect(lines).not_to be_empty
    expect(lines.first).to be_a(Shoko::Core::Models::DisplayLine)

    window = service.wrap_window(doc, 0, 20, offset: 0, length: 2, config: double('Config', get: false))
    expect(window.length).to eq(2)
  end
end
