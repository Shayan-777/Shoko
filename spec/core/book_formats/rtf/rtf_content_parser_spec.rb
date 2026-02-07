# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Rtf::RtfContentParser do
  it 'parses HTML paragraphs into content blocks' do
    html = '<p>First paragraph.</p><p>Second paragraph.</p>'
    blocks = described_class.new(html).parse

    expect(blocks).to be_a(Array)
    expect(blocks.length).to eq(2)
    expect(blocks[0].type).to eq(:paragraph)
    expect(blocks[0].segments.first.text).to include('First paragraph')
    expect(blocks[1].segments.first.text).to include('Second paragraph')
  end

  it 'parses headings' do
    html = '<html><body><h1>Chapter Title</h1><p>Body text.</p></body></html>'
    blocks = described_class.new(html).parse

    heading = blocks.find { |b| b.type == :heading }
    expect(heading).not_to be_nil
    expect(heading.segments.first.text).to include('Chapter Title')
  end

  it 'parses bold and italic styles' do
    html = '<html><body><p><b>Bold</b> and <i>italic</i> text.</p></body></html>'
    blocks = described_class.new(html).parse

    paragraph = blocks.find { |b| b.type == :paragraph }
    expect(paragraph).not_to be_nil
    bold_seg = paragraph.segments.find { |s| s.styles[:bold] }
    italic_seg = paragraph.segments.find { |s| s.styles[:italic] }
    expect(bold_seg).not_to be_nil
    expect(italic_seg).not_to be_nil
  end

  it 'returns empty array for blank input' do
    expect(described_class.new('').parse).to eq([])
    expect(described_class.new('   ').parse).to eq([])
  end

  it 'handles nil-like input gracefully' do
    expect(described_class.new(nil).parse).to eq([])
  end
end
