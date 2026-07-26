# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::RssArticleLayout do
  # Referenced through methods rather than constants so the spec does not
  # define constants on Object.
  def ansi = Shoko::Shared::Terminal::Ansi
  def palette = Shoko::Adapters::Ui::Components::StatusBar::Palette

  def blocks_for(html)
    Shoko::Core::Models::ContentBlockPayload.dump(
      Shoko::Adapters::Rss::ArticleBlockParser.new.parse(html)
    )
  end

  def lines_for(html, width: 40)
    described_class.new(width: width).call(blocks_for(html))
  end

  # Rows are ReadingLine values; these read their drawn text back.
  def texts(lines) = lines.map { |line| line.segments.map(&:first).join }

  def styles_for(lines, needle)
    lines.flat_map(&:segments).select { |text, _style| text.include?(needle) }.map(&:last)
  end

  describe 'structure' do
    it 'separates blocks with a blank line' do
      expect(texts(lines_for('<p>One.</p><p>Two.</p>'))).to eq(['One.', '', 'Two.'])
    end

    it 'keeps consecutive list items tight' do
      expect(texts(lines_for('<ul><li>One</li><li>Two</li></ul>'))).to eq(['• One', '• Two'])
    end

    it 'keeps consecutive code lines tight' do
      expect(texts(lines_for("<pre>a\nb</pre>"))).to eq(['  a', '  b'])
    end

    it 'separates a list from the paragraph before it' do
      expect(texts(lines_for('<p>Intro</p><ul><li>One</li></ul>'))).to eq(['Intro', '', '• One'])
    end

    it 'indents nested list items and aligns wrapped rows under the text' do
      lines = texts(lines_for('<ul><li>outer</li><ul><li>an inner item that wraps here</li></ul></ul>', width: 20))

      expect(lines.first).to eq('• outer')
      # Nested levels take their own bullet so depth reads at a glance.
      expect(lines[1]).to start_with('  ◦ ')
      expect(lines[2]).to match(/\A {4}\S/)
    end

    it 'draws a quote gutter on every row of the quote' do
      lines = texts(lines_for('<blockquote><p>a quote long enough to wrap twice</p></blockquote>', width: 22))

      expect(lines).to all(start_with('│ '))
      expect(lines.length).to be > 1
    end

    it 'draws a rule between sections' do
      expect(texts(lines_for('<p>A</p><hr><p>B</p>', width: 30))).to eq(['A', '', '──────────', '', 'B'])
    end

    it 'renders nothing for an article with no blocks' do
      expect(described_class.new(width: 40).call([])).to eq([])
    end
  end

  describe 'inline emphasis' do
    it 'makes headings bold' do
      expect(styles_for(lines_for('<h2>Titel</h2>'), 'Titel').first).to include(ansi::BOLD)
    end

    it 'bolds a strong run without bolding the rest of the sentence' do
      lines = lines_for('<p>plain <strong>strong</strong> plain</p>')

      expect(styles_for(lines, 'strong').first).to include(ansi::BOLD)
      expect(styles_for(lines, 'plain ').first).not_to include(ansi::BOLD)
    end

    it 'italicises an emphasis run' do
      expect(styles_for(lines_for('<p><em>slanted</em></p>'), 'slanted').first).to include(ansi::ITALIC)
    end

    it 'gives links the accent colour' do
      expect(styles_for(lines_for('<p><a href="https://x.de">link</a></p>'), 'link').first)
        .to include(palette::LIST_POINTER_FG)
    end

    it 'keeps emphasis on both rows when a styled run wraps' do
      lines = lines_for("<p><strong>#{(['word'] * 12).join(' ')}</strong></p>", width: 20)
      bold_rows = lines.map { |line| line.segments.map(&:last) }
                       .select { |styles| styles.any? { |s| s.include?(ansi::BOLD) } }

      expect(lines.length).to be > 1
      expect(bold_rows.length).to eq(lines.length)
    end

    it 'composes emphasis onto the block tone rather than replacing it' do
      style = styles_for(lines_for('<blockquote><p><strong>loud</strong></p></blockquote>'), 'loud').first

      expect(style).to include(ansi::BOLD)
      expect(style).to include(palette::LANDING_DIM_FG)
    end
  end

  describe 'wrapping' do
    it 'never exceeds the given width' do
      html = "<p>#{(['Silbentrennung'] * 10).join(' ')}</p>"

      texts(lines_for(html, width: 24)).each do |line|
        expect(Shoko::Shared::Terminal::TextMetrics.visible_length(line)).to be <= 24
      end
    end

    it 'measures wide characters in cells, not characters' do
      lines = texts(lines_for("<p>#{'あ' * 30}</p>", width: 20))

      lines.each do |line|
        expect(Shoko::Shared::Terminal::TextMetrics.visible_length(line)).to be <= 20
      end
    end

    it 'splits a single word wider than the line instead of overflowing' do
      lines = texts(lines_for("<p>#{'x' * 60}</p>", width: 20))

      expect(lines.length).to be > 1
      lines.each { |line| expect(line.length).to be <= 20 }
    end

    it 'does not start a row with a stray space' do
      lines = texts(lines_for("<p>#{(['alpha beta'] * 8).join(' ')}</p>", width: 18))

      expect(lines).to all(satisfy { |line| !line.start_with?(' ') })
    end

    it 'clips code rather than rewrapping it' do
      lines = texts(lines_for("<pre>#{'a' * 80}</pre>", width: 20))

      expect(lines.length).to eq(1)
      expect(Shoko::Shared::Terminal::TextMetrics.visible_length(lines.first)).to be <= 20
    end

    it 'merges adjacent runs that share a style' do
      row = lines_for('<p>one two three</p>').first

      expect(row.segments.length).to eq(1)
    end
  end

  describe 'stored payloads' do
    it 'renders blocks that have been through a JSON round trip' do
      payload = JSON.parse(JSON.generate(blocks_for('<h2>Titel</h2><p>Text.</p>')))

      expect(texts(described_class.new(width: 40).call(payload))).to eq(['Titel', '', 'Text.'])
    end
  end
end
