# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Epub::XHTMLContentParser do
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

  it 'keeps nested list items as their own deeper-level items' do
    html = '<body><ul><li>Alpha<ul><li>Sub one</li></ul></li><li>Beta</li></ul></body>'

    blocks = described_class.new(html).parse

    expect(blocks.map(&:type)).to eq(%i[list_item list_item list_item])
    expect(blocks.map(&:level)).to eq([1, 2, 1])
    expect(blocks.map(&:text)).to eq(['Alpha', 'Sub one', 'Beta'])
    expect(blocks[1].metadata[:marker]).to eq('◦')
  end

  it 'renders multi-paragraph blockquotes as separate quote blocks' do
    html = '<body><blockquote><p>First.</p><p>Second.</p></blockquote></body>'

    blocks = described_class.new(html).parse

    expect(blocks.map(&:type)).to eq(%i[quote quote])
    expect(blocks.map(&:text)).to eq(['First.', 'Second.'])
    expect(blocks).to all(satisfy { |block| block.metadata[:quoted] })
  end

  it 'honors ordered-list start, item value, and numbering type' do
    html = '<body><ol start="5" type="i"><li>Fifth</li><li value="9">Ninth</li><li>Tenth</li></ol></body>'

    blocks = described_class.new(html).parse

    expect(blocks.map { |block| block.metadata[:marker] }).to eq(['v.', 'ix.', 'x.'])
  end

  it 'decodes Latin-1 and typographic named entities' do
    html = '<body><p>Caf&eacute; &sect; r&eacute;sum&eacute; &dagger; &auml;</p></body>'

    blocks = described_class.new(html).parse

    expect(blocks.first.text).to eq('Café § résumé † ä')
  end

  it 'centers content inside a center tag' do
    blocks = described_class.new('<body><center>Scene Break</center></body>').parse

    expect(blocks.first.metadata[:align]).to eq(:center)
  end

  it 'applies inline style attributes on block-level elements to their segments' do
    blocks = described_class.new('<body><div style="font-style:italic">A letter.</div></body>').parse

    expect(blocks.first.segments.first.styles[:italic]).to be(true)
  end

  it 'styles cite, mark, small, and font color runs' do
    html = '<body><p><cite>Title</cite> <mark>hit</mark> <small>fine</small> <font color="red">warm</font></p></body>'

    blocks = described_class.new(html).parse
    styles = blocks.first.segments.map(&:styles)

    expect(styles).to include(hash_including(italic: true))
    expect(styles).to include(hash_including(highlight: true))
    expect(styles).to include(hash_including(small: true))
    expect(styles).to include(hash_including(fg: 'red'))
  end

  it 'maps definition lists to term and definition paragraphs' do
    html = '<body><dl><dt>Term</dt><dd>The definition.</dd></dl></body>'

    blocks = described_class.new(html).parse

    expect(blocks[0].metadata[:role]).to eq(:term)
    expect(blocks[0].segments.first.styles[:bold]).to be(true)
    expect(blocks[1].metadata[:role]).to eq(:definition)
    expect(blocks[1].metadata[:indent_left]).to eq(4)
  end

  it 'includes alt text in image placeholders' do
    blocks = described_class.new('<body><img src="pic.png" alt="A pic"/></body>').parse

    expect(blocks.first.text).to include('[Image: A pic]')
  end

  it 'captures table captions into table metadata' do
    html = '<body><table><caption>Results</caption><tr><td>1</td></tr></table></body>'

    blocks = described_class.new(html).parse
    table_block = blocks.find { |block| block.type == :table }

    expect(table_block.metadata[:table][:caption]).to eq('Results')
  end

  it 'keeps per-run styles inside preformatted blocks' do
    html = "<body><pre>plain <b>bold</b>\nnext line</pre></body>"

    blocks = described_class.new(html).parse
    code_block = blocks.find { |block| block.type == :code }

    expect(code_block.segments.map(&:styles)).to include(hash_including(bold: true))
    expect(code_block.text).to include("\n")
  end

  it 'marks hgroup title paragraphs as subtitles but not the heading itself' do
    html = '<body><hgroup><h2>IV</h2><p>The Real Title</p></hgroup></body>'

    blocks = described_class.new(html).parse

    expect(blocks[0].type).to eq(:heading)
    expect(blocks[0].metadata[:role]).to be_nil
    expect(blocks[1].metadata[:role]).to eq(:subtitle)
  end

  it 'renders epub noteref links as superscript' do
    html = '<body xmlns:epub="http://www.idpf.org/2007/ops">' \
           '<p>text<a href="notes.xhtml#n1" epub:type="noteref">1</a></p></body>'

    blocks = described_class.new(html).parse
    noteref = blocks.first.segments.find { |segment| segment.styles[:link] }

    expect(noteref.styles[:superscript]).to be(true)
  end

  it 'marks blocks inside epub verse containers with the verse role' do
    html = '<body xmlns:epub="http://www.idpf.org/2007/ops">' \
           '<section epub:type="z3998:poem"><p>A verse line</p></section></body>'

    blocks = described_class.new(html).parse

    expect(blocks.first.metadata[:role]).to eq(:verse)
  end

  describe 'with a style resolver' do
    def parse_with_css(css, html)
      catalog = Shoko::Adapters::BookSources::Css::StyleCatalog.new(stylesheets: { 'style.css' => css })
      raw = %(<html><head><link href="style.css" rel="stylesheet"/></head><body>#{html}</body></html>)
      resolver = catalog.resolver_for(chapter_source_path: 'ch1.xhtml', raw_content: raw)
      described_class.new(raw, style_resolver: resolver).parse
    end

    it 'applies class-driven inline styles and block typography' do
      css = '.emph { font-style: italic } p { text-indent: 1em; margin: 0 } .c { text-align: center }'
      blocks = parse_with_css(css, '<p class="c">Centered</p><p>Body <span class="emph">soft</span> text</p>')

      expect(blocks[0].metadata[:align]).to eq(:center)
      expect(blocks[1].metadata[:first_line_indent]).to eq(2)
      expect(blocks[1].metadata[:spacing_after]).to eq(0)
      italic = blocks[1].segments.find { |segment| segment.styles[:italic] }
      expect(italic.text).to eq('soft')
    end

    it 'prunes display:none subtrees but keeps their anchors on the next block' do
      css = '.hidden { display: none }'
      blocks = parse_with_css(css, '<p class="hidden"><span id="pg5"/>gone</p><p>visible</p>')

      expect(blocks.length).to eq(1)
      expect(blocks.first.text).to eq('visible')
      expect(blocks.first.metadata[:anchors]).to include('pg5')
    end

    it 'promotes display:block spans to their own blocks' do
      css = 'span.line { display: block; padding-left: 1em; text-indent: -1em }'
      blocks = parse_with_css(css, '<p><span class="line">one</span><span class="line">two</span></p>')

      expect(blocks.map(&:text)).to eq(%w[one two])
      expect(blocks.first.metadata[:hanging_indent]).to eq(2)
    end

    it 'groups blocks inside bordered containers into a boxed group' do
      css = 'div.note { border: 1px solid #333 } div.note p { margin: 0 }'
      blocks = parse_with_css(css, '<div class="note"><p>a</p><p>b</p></div>')

      expect(blocks.map { |block| block.metadata[:box_group] }.uniq.length).to eq(1)
      expect(blocks.first.metadata[:box_group]).not_to be_nil
    end
  end

  it 'parses tables even when chapter text includes raw code operators that break strict XML' do
    html = <<~HTML
      <html>
        <body>
          <table>
            <tr><th>Decimal</th><th>Hex</th></tr>
            <tr><td>0</td><td>00</td></tr>
          </table>
          <pre>#include &lt;stdio.h&gt;
printf("%d", a&0x80); while( i<8 ) { a<<=1; }</pre>
        </body>
      </html>
    HTML

    parser = described_class.new(html)
    blocks = parser.parse

    expect(blocks.map(&:type)).to include(:table)
    expect(blocks.map(&:type)).to include(:code)

    table_block = blocks.find { |block| block.type == :table }
    expect(table_block.metadata[:table][:rows].length).to eq(2)
    expect(table_block.metadata[:table][:rows].first[:cells].map { |cell| cell[:text] }).to eq(%w[Decimal Hex])

    code_block = blocks.find { |block| block.type == :code }
    expect(code_block.text).to include('#include <stdio.h>')
    expect(code_block.text).to include('a&0x80')
    expect(code_block.text).to include('i<8')
  end
end
