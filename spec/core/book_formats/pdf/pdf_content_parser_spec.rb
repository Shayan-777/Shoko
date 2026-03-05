# frozen_string_literal: true

require 'json'
require 'spec_helper'
require_relative '../../../../lib/shoko/core/book_formats/pdf/pdf_content_parser'

RSpec.describe Shoko::Core::BookFormats::Pdf::PdfContentParser do
  def payload(lines)
    JSON.generate(
      {
        format: 'pdf-layout-v1',
        lines: lines,
      }
    )
  end

  it 'preserves heading and epigraph semantics from layout payloads' do
    raw = payload([
                    { text: '4', x: 150.0, italic: false },
                    { break: true },
                    { text: 'The glory of my boyhood years was my father ...', x: 220.0, italic: true },
                    { text: 'equal to the white man; we resolved to prove it.', x: 224.0, italic: true },
                    { text: 'PAUL ROBESON', x: 248.0, italic: false },
                    { break: true },
                    { text: 'Changing', x: 156.0, italic: false },
                    { break: true },
                    { text: 'Hope has always been a scarce commodity in the Black community.', x: 72.0, italic: false },
                    { text: 'Claude Brown wrote this in Manchild in the Promised Land.', x: 74.0, italic: false },
                  ])

    blocks = described_class.new(raw).parse

    expect(blocks.map(&:type)).to eq([:heading, :quote, :paragraph, :heading, :paragraph])
    expect(blocks[0].metadata[:align]).to eq(:center)
    expect(blocks[0].text).to eq('4')

    epigraph = blocks[1]
    expect(epigraph.metadata[:style]).to eq(:epigraph)
    expect(epigraph.metadata[:align]).to eq(:right)
    expect(epigraph.segments.any? { |segment| segment.styles[:italic] }).to be(true)

    attribution = blocks[2]
    expect(attribution.metadata[:style]).to eq(:attribution)
    expect(attribution.metadata[:align]).to eq(:right)
    expect(attribution.text).to eq('PAUL ROBESON')

    expect(blocks[3].text).to eq('Changing')
    expect(blocks[4].metadata[:align]).to be_nil
  end

  it 'falls back to paragraph parsing for legacy plain text payloads' do
    raw = "First paragraph line\ncontinues.\n\nSecond paragraph."

    blocks = described_class.new(raw).parse

    expect(blocks.length).to eq(2)
    expect(blocks.map(&:type)).to eq([:paragraph, :paragraph])
    expect(blocks[0].text).to include('First paragraph line continues.')
    expect(blocks[1].text).to eq('Second paragraph.')
  end

  it 'parses top-level array layout payloads from older PDF caches' do
    raw = JSON.generate(
      [
        { text: '4', x: 150.0, italic: false },
        { break: true },
        { text: 'A right aligned epigraph line.', x: 220.0, italic: nil },
        { text: 'PAUL ROBESON', x: 220.0, italic: false },
        { break: true },
        { text: 'Body text line.', x: 72.0, italic: false },
      ]
    )

    blocks = described_class.new(raw).parse

    expect(blocks.map(&:type)).to eq([:heading, :quote, :paragraph, :paragraph])
    expect(blocks[0].text).to eq('4')
    expect(blocks[1].metadata[:align]).to eq(:right)
    expect(blocks[2].metadata[:style]).to eq(:attribution)
    expect(blocks[3].text).to eq('Body text line.')
  end

  it 'parses double-encoded JSON layout payload strings' do
    lines = [
      { text: 'Chapter 1', x: 110.0, italic: false },
      { break: true },
      { text: 'Opening paragraph text.', x: 72.0, italic: false },
    ]
    raw = JSON.generate(JSON.generate(lines))

    blocks = described_class.new(raw).parse

    expect(blocks.length).to eq(2)
    expect(blocks[0].text).to eq('Chapter 1')
    expect(blocks[1].text).to eq('Opening paragraph text.')
  end

  it 'recovers text from escaped JSON-ish payloads instead of rendering raw hashes' do
    raw = '\\"text\\":\\"motorcycle\\",\\"x\\":6.65625,\\"italic\\":null},{\\"text\\":\\"going so fast\\",\\"x\\":6.65625'

    blocks = described_class.new(raw).parse

    expect(blocks).not_to be_empty
    expect(blocks.first.text).to include('motorcycle')
    expect(blocks.first.text).not_to include('\\"text\\"')
  end

  it 'keeps centered attribution signatures out of heading classification' do
    raw = payload([
                    { text: '12', x: 150.0, italic: false },
                    { break: true },
                    { text: 'What is property? Property is theft.', x: 190.0, italic: false },
                    { text: 'PIERRE-JOSEPH PROUDHON, 1840', x: 250.0, italic: false },
                    { break: true },
                    { text: 'The brigand . . . is the true and only revolutionary.', x: 190.0, italic: false },
                    { text: 'BAKUNIN, 1870', x: 485.0, italic: false },
                    { break: true },
                    { text: 'Scoring', x: 280.0, italic: false },
                    { break: true },
                    { text: 'I first studied law to become a better burglar.', x: 72.0, italic: false },
                  ])

    blocks = described_class.new(raw).parse

    expect(blocks.map(&:type)).to eq([:heading, :quote, :paragraph, :quote, :paragraph, :heading, :paragraph])
    expect(blocks[1].metadata[:style]).to eq(:epigraph)
    expect(blocks[2].metadata[:style]).to eq(:attribution)
    expect(blocks[2].metadata[:align]).to eq(:right)
    expect(blocks[2].text).to eq('PIERRE-JOSEPH PROUDHON, 1840')
    expect(blocks[3].metadata[:style]).to eq(:epigraph)
    expect(blocks[4].metadata[:style]).to eq(:attribution)
    expect(blocks[4].text).to eq('BAKUNIN, 1870')
    expect(blocks[5].text).to eq('Scoring')
  end

  it 'does not classify mid-body mixed-italic lines as epigraph blockquotes' do
    raw = payload([
                    { text: '12', x: 150.0, italic: false, italic_ratio: 0.0 },
                    { break: true },
                    { text: 'What is property? Property is theft.', x: 190.0, italic: true, italic_ratio: 1.0 },
                    { text: 'PIERRE-JOSEPH PROUDHON, 1840', x: 250.0, italic: false, italic_ratio: 0.0 },
                    { break: true },
                    { text: 'Scoring', x: 150.0, italic: false, italic_ratio: 0.0 },
                    { break: true },
                    { text: 'I first studied law to become a better burglar.', x: 72.0, italic: false, italic_ratio: 0.0 },
                    { text: 'Figuring I might get busted at any time and wanting to be ready.', x: 72.0, italic: false, italic_ratio: 0.0 },
                    { text: 'studied the California penal code and books like California Criminal', x: 110.0, italic: false, italic_ratio: 0.34 },
                    { text: 'Evidence and California Criminal Law by Fricke and Alarcon,', x: 110.0, italic: false, italic_ratio: 0.31 },
                    { text: 'concentrating on those areas that were somewhat vague.', x: 72.0, italic: false, italic_ratio: 0.0 },
                  ])

    blocks = described_class.new(raw).parse
    scoring_idx = blocks.index { |block| block.text == 'Scoring' }
    trailing_blocks = blocks[(scoring_idx + 1)..] || []

    expect(trailing_blocks.map(&:type)).to all(eq(:paragraph))
    expect(trailing_blocks.map(&:text).join(' ')).to include('studied the California penal code')
  end

  it 'parses multi-line epigraph attributions with mixed-case source titles' do
    raw = payload([
                    { text: '11', x: 299.56, italic: false, italic_ratio: 0.0 },
                    { text: 'As for the future, the young streetcorner man has a fairly good picture of it. .', x: 126.65, italic: true, italic_ratio: 1.0 },
                    { text: '. . It is a future in which everything is uncertain except the ultimate', x: 126.65, italic: true, italic_ratio: 1.0 },
                    { text: 'destruction of his hopes and the eventual realization of his fears. The most', x: 126.65, italic: true, italic_ratio: 1.0 },
                    { text: 'he can reasonably look forward to is that these things do not come too soon.', x: 126.65, italic: true, italic_ratio: 1.0 },
                    { text: 'ELLIOT LIEBOW, Tally’s Corner', x: 501.89, italic: true, italic_ratio: 1.0 },
                    { break: true },
                    { text: 'The Brothers on the Block', x: 205.98, italic: false, italic_ratio: 0.0 },
                    { break: true },
                    { text: 'Nothing we had done on the campus related to the conditions of the brothers on the block.', x: 6.65, italic: false, italic_ratio: 0.0 },
                  ])

    blocks = described_class.new(raw).parse

    expect(blocks.map(&:type)).to eq([:heading, :quote, :paragraph, :heading, :paragraph])
    expect(blocks[1].metadata[:style]).to eq(:epigraph)
    expect(blocks[2].metadata[:style]).to eq(:attribution)
    expect(blocks[2].metadata[:align]).to eq(:right)
    expect(blocks[2].text).to eq('ELLIOT LIEBOW, Tally’s Corner')
    expect(blocks[3].text).to eq('The Brothers on the Block')
  end

  it 'recognizes title-cased author and source attribution signatures' do
    raw = payload([
                    { text: '11', x: 299.56, italic: false },
                    { break: true },
                    { text: 'This is a quote sentence.', x: 126.65, italic: true, italic_ratio: 1.0 },
                    { text: "Eliot Liebow, Tally's Corner", x: 501.89, italic: false, italic_ratio: 0.0 },
                    { break: true },
                    { text: 'Body paragraph starts here.', x: 6.65, italic: false },
                  ])

    blocks = described_class.new(raw).parse

    expect(blocks.map(&:type)).to eq([:heading, :quote, :paragraph, :paragraph])
    expect(blocks[2].metadata[:style]).to eq(:attribution)
    expect(blocks[2].metadata[:align]).to eq(:right)
    expect(blocks[2].text).to eq("Eliot Liebow, Tally's Corner")
  end

  it 'falls back to plain paragraph parsing when layout payload json is malformed' do
    raw = '{"lines":['

    blocks = described_class.new(raw).parse

    expect(blocks).not_to be_empty
    expect(blocks.map(&:type)).to eq([:paragraph])
    expect(blocks.first.text).to include('{"lines":[')
  end

  it 'ignores invalid numeric alignment hints instead of raising' do
    raw = payload([
                    { text: 'Preface', x: 'oops', italic: false },
                    { break: true },
                    { text: 'Body text should still parse.', x: 72.0, italic: false },
                  ])

    blocks = nil
    expect { blocks = described_class.new(raw).parse }.not_to raise_error
    expect(blocks.length).to eq(2)
    expect(blocks.first.text).to eq('Preface')
    expect(blocks.last.text).to eq('Body text should still parse.')
  end
end
