# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Rss::ArticleBlockParser do
  subject(:parser) { described_class.new }

  def parse(html) = parser.parse(html)

  def shapes(html)
    parse(html).map { |block| [block.type, block.text] }
  end

  describe 'block structure' do
    it 'keeps headings with their level' do
      blocks = parse('<h1>One</h1><h3>Three</h3>')

      expect(blocks.map { |b| [b.type, b.level, b.text] }).to eq(
        [[:heading, 1, 'One'], [:heading, 3, 'Three']]
      )
    end

    it 'separates paragraphs' do
      expect(shapes('<p>First.</p><p>Second.</p>')).to eq(
        [[:paragraph, 'First.'], [:paragraph, 'Second.']]
      )
    end

    it 'treats a <br> as a line break between blocks' do
      expect(shapes('<p>Before.<br>After.</p>')).to eq(
        [[:paragraph, 'Before.'], [:paragraph, 'After.']]
      )
    end

    it 'marks unordered list items with a bullet and their depth' do
      blocks = parse('<ul><li>One</li><li>Two</li></ul>')

      expect(blocks.map { |b| [b.type, b.level, b.metadata[:marker], b.text] }).to eq(
        [[:list_item, 1, '•', 'One'], [:list_item, 1, '•', 'Two']]
      )
    end

    it 'numbers ordered list items' do
      blocks = parse('<ol><li>One</li><li>Two</li><li>Three</li></ol>')

      expect(blocks.map { |b| b.metadata[:marker] }).to eq(['1.', '2.', '3.'])
    end

    it 'tracks nested list depth' do
      blocks = parse('<ul><li>Outer</li><ul><li>Inner</li></ul></ul>')

      expect(blocks.map { |b| [b.level, b.text] }).to eq([[1, 'Outer'], [2, 'Inner']])
    end

    it 'types a paragraph inside a blockquote as a quote' do
      expect(shapes('<blockquote><p>Quoted.</p></blockquote><p>Plain.</p>')).to eq(
        [[:quote, 'Quoted.'], [:paragraph, 'Plain.']]
      )
    end

    it 'emits one code block per source line and keeps indentation' do
      expect(shapes("<pre>def x\n  y\nend</pre>")).to eq(
        [[:code, 'def x'], [:code, '  y'], [:code, 'end']]
      )
    end

    it 'keeps horizontal rules as structural blocks' do
      expect(shapes('<p>A</p><hr><p>B</p>')).to eq(
        [[:paragraph, 'A'], [:rule, ''], [:paragraph, 'B']]
      )
    end

    it 'types figure captions so they can be rendered as secondary text' do
      expect(shapes('<figcaption>Bild: Foo</figcaption>')).to eq([[:caption, 'Bild: Foo']])
    end
  end

  describe 'inline styles' do
    it 'captures bold, italic, and code runs' do
      blocks = parse('<p>a <strong>b</strong> <em>c</em> <code>d</code></p>')

      expect(blocks.first.segments.map { |s| [s.text, s.styles] }).to eq(
        [['a ', {}], ['b', { bold: true }], [' ', {}], ['c', { italic: true }], [' ', {}], ['d', { code: true }]]
      )
    end

    it 'keeps a link target alongside its text' do
      blocks = parse('<p>see <a href="https://example.com/x">here</a></p>')
      link = blocks.first.segments.find { |s| s.styles[:link] }

      expect(link.text).to eq('here')
      expect(link.styles[:href]).to eq('https://example.com/x')
    end

    it 'nests styles' do
      blocks = parse('<p><strong>bold <em>and italic</em></strong></p>')

      expect(blocks.first.segments.map(&:styles)).to eq(
        [{ bold: true }, { bold: true, italic: true }]
      )
    end

    it 'tolerates a link with no href' do
      blocks = parse('<p><a>bare</a></p>')

      expect(blocks.first.segments.map(&:styles)).to eq([{ link: true }])
    end
  end

  describe 'hostile and messy markup' do
    it 'drops script, style, and other non-prose containers with their contents' do
      expect(shapes('<p>Keep.</p><script>alert("x")</script><style>.a{}</style>')).to eq(
        [[:paragraph, 'Keep.']]
      )
    end

    it 'survives unclosed tags' do
      expect(shapes('<p>One<p>Two<p>Three')).to eq(
        [[:paragraph, 'One'], [:paragraph, 'Two'], [:paragraph, 'Three']]
      )
    end

    it 'ignores unknown tags but keeps their text' do
      expect(shapes('<p>a <custom-thing data-x="1">b</custom-thing> c</p>')).to eq(
        [[:paragraph, 'a b c']]
      )
    end

    it 'decodes entities' do
      expect(shapes('<p>Gr&uuml;&szlig;e &amp; mehr &#8212; ja</p>')).to eq(
        [[:paragraph, 'Grüße & mehr — ja']]
      )
    end

    it 'collapses whitespace and trims block edges' do
      expect(shapes("<p>\n   spaced   out\n </p>")).to eq([[:paragraph, 'spaced out']])
    end

    it 'drops empty blocks and stray rules' do
      expect(parse('<hr><p></p><p>  </p><hr><hr><p>Real</p><hr>').map(&:type)).to eq([:paragraph])
    end

    it 'returns nothing for empty input' do
      expect(parse('')).to eq([])
      expect(parse(nil)).to eq([])
    end

    it 'does not raise on a truncated tag' do
      expect { parse('<p>text</p><div class="x') }.not_to raise_error
    end

    it 'closes an unbalanced blockquote without swallowing the rest' do
      expect(shapes('<blockquote><p>Q</p><p>Still.</p>')).to eq(
        [[:quote, 'Q'], [:quote, 'Still.']]
      )
    end
  end
end
