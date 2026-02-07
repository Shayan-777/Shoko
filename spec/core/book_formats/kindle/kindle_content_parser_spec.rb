# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Kindle::KindleContentParser do
  it 'parses simple HTML paragraphs into content blocks' do
    html = '<p>First paragraph.</p><p>Second paragraph.</p>'
    blocks = described_class.new(html).parse

    expect(blocks).to be_a(Array)
    expect(blocks.length).to eq(2)
    expect(blocks[0].type).to eq(:paragraph)
    expect(blocks[0].segments.first.text).to include('First paragraph')
    expect(blocks[1].segments.first.text).to include('Second paragraph')
  end

  it 'parses headings in a body context' do
    html = '<html><body><h1>Chapter Title</h1><p>Body text.</p></body></html>'
    blocks = described_class.new(html).parse

    heading = blocks.find { |b| b.type == :heading }
    expect(heading).not_to be_nil
    expect(heading.segments.first.text).to include('Chapter Title')
  end

  it 'parses bold and italic inline styles' do
    html = '<html><body><p><b>Bold</b> and <i>italic</i> text.</p></body></html>'
    blocks = described_class.new(html).parse

    paragraph = blocks.find { |b| b.type == :paragraph }
    expect(paragraph).not_to be_nil
    segments = paragraph.segments
    bold_seg = segments.find { |s| s.styles[:bold] }
    italic_seg = segments.find { |s| s.styles[:italic] }

    expect(bold_seg).not_to be_nil
    expect(italic_seg).not_to be_nil
  end

  it 'handles MOBI-style HTML with font tags' do
    html = '<p><font size="4"><b>Chapter 1</b></font></p><p>It was the best of times.</p>'
    blocks = described_class.new(html).parse

    expect(blocks.length).to be >= 1
    text = blocks.flat_map { |b| b.segments.map(&:text) }.join
    expect(text).to include('Chapter 1')
  end

  it 'handles AZW3/KF8 XHTML with namespace' do
    html = <<~XHTML
      <?xml version="1.0" encoding="UTF-8"?>
      <html xmlns="http://www.w3.org/1999/xhtml">
        <body>
          <p class="calibre_">Hello from KF8.</p>
        </body>
      </html>
    XHTML
    blocks = described_class.new(html).parse

    expect(blocks).not_to be_empty
    text = blocks.flat_map { |b| b.segments.map(&:text) }.join
    expect(text).to include('Hello from KF8')
  end

  it 'returns empty array for blank input' do
    expect(described_class.new('').parse).to eq([])
    expect(described_class.new('   ').parse).to eq([])
  end

  it 'handles nil-like input gracefully' do
    expect(described_class.new(nil).parse).to eq([])
  end
end
