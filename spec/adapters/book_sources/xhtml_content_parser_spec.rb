# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Epub::XHTMLContentParser do
  it 'parses paragraphs into content blocks with segments' do
    parser = described_class.new('<html><body><p>Hello <em>World</em></p></body></html>')

    blocks = parser.parse

    expect(blocks).not_to be_empty
    first = blocks.first
    expect(first).to be_a(Shoko::Core::Models::ContentBlock)
    expect(first.segments).not_to be_empty
    expect(first.text).to include('Hello')
  end

  it 'parses tables into table blocks with metadata' do
    html = <<~HTML
      <html>
        <body>
          <table>
            <thead>
              <tr><th>Header A</th><th>Header B</th></tr>
            </thead>
            <tbody>
              <tr><td>Cell 1</td><td>Cell 2</td></tr>
            </tbody>
          </table>
        </body>
      </html>
    HTML

    parser = described_class.new(html)
    blocks = parser.parse

    table_block = blocks.find { |block| block.type == :table }
    expect(table_block).not_to be_nil

    table = table_block.metadata[:table]
    expect(table[:rows].length).to eq(2)
    expect(table[:rows].first[:header]).to be(true)
    expect(table[:rows].first[:cells].first[:text]).to eq('Header A')
  end

  it 'captures paragraph and table cell alignment' do
    html = <<~HTML
      <html>
        <body>
          <p style="text-align: center">Centered text</p>
          <table>
            <tr><td style="text-align: right">42</td></tr>
          </table>
        </body>
      </html>
    HTML

    parser = described_class.new(html)
    blocks = parser.parse

    paragraph = blocks.find { |block| block.type == :paragraph }
    expect(paragraph.metadata[:align]).to eq(:center)

    table_block = blocks.find { |block| block.type == :table }
    cell_align = table_block.metadata[:table][:rows].first[:cells].first[:align]
    expect(cell_align).to eq(:right)
  end

  it 'attaches anchor ids to block metadata' do
    html = <<~HTML
      <html>
        <body>
          <h2 id="section-1">Section</h2>
          <p><a id="para-anchor"></a>Paragraph</p>
        </body>
      </html>
    HTML

    parser = described_class.new(html)
    blocks = parser.parse

    heading = blocks.find { |block| block.type == :heading }
    paragraph = blocks.find { |block| block.type == :paragraph }

    expect(heading.metadata[:anchors]).to include('section-1')
    expect(paragraph.metadata[:anchors]).to include('para-anchor')
  end

  it 'preserves underline, strikethrough, superscript, and subscript inline styles' do
    html = <<~HTML
      <html>
        <body>
          <p><u>underline</u> <del>deleted</del> <sup>2</sup> <sub>n</sub></p>
        </body>
      </html>
    HTML

    blocks = described_class.new(html).parse
    paragraph = blocks.find { |block| block.type == :paragraph }

    expect(paragraph).not_to be_nil
    expect(paragraph.segments.any? { |segment| segment.styles[:underline] }).to be(true)
    expect(paragraph.segments.any? { |segment| segment.styles[:strikethrough] }).to be(true)
    expect(paragraph.segments.any? { |segment| segment.styles[:superscript] }).to be(true)
    expect(paragraph.segments.any? { |segment| segment.styles[:subscript] }).to be(true)
  end

  it 'maps vertical-align styles to superscript/subscript segments' do
    html = <<~HTML
      <html>
        <body>
          <p><span style="vertical-align: super">2</span> and <span style="vertical-align: sub">n</span></p>
        </body>
      </html>
    HTML

    blocks = described_class.new(html).parse
    paragraph = blocks.find { |block| block.type == :paragraph }

    expect(paragraph).not_to be_nil
    expect(paragraph.segments.any? { |segment| segment.styles[:superscript] && segment.text.include?('2') }).to be(true)
    expect(paragraph.segments.any? { |segment| segment.styles[:subscript] && segment.text.include?('n') }).to be(true)
  end
end
