# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Fb2::Fb2ContentParser do
  it 'maps title, epigraph, and attribution to aligned semantic blocks' do
    xml = <<~XML
      <section>
        <title><p>4</p></title>
        <epigraph>
          <p>The glory of my boyhood years was my father ...</p>
          <text-author>PAUL ROBESON</text-author>
        </epigraph>
        <title><p>Changing</p></title>
        <p>Hope has always been a scarce commodity in the Black community.</p>
      </section>
    XML

    blocks = described_class.new(xml).parse

    expect(blocks.map(&:type)).to eq([:heading, :blockquote, :paragraph, :heading, :paragraph])

    expect(blocks[0].metadata[:align]).to eq(:center)
    expect(blocks[0].text).to eq('4')

    epigraph = blocks[1]
    expect(epigraph.metadata[:style]).to eq(:epigraph)
    expect(epigraph.metadata[:align]).to eq(:right)
    expect(epigraph.segments.all? { |segment| segment.styles[:italic] }).to be(true)

    attribution = blocks[2]
    expect(attribution.metadata[:style]).to eq(:attribution)
    expect(attribution.metadata[:align]).to eq(:right)
    expect(attribution.text).to eq('PAUL ROBESON')

    expect(blocks[3].metadata[:align]).to eq(:center)
    expect(blocks[3].text).to eq('Changing')
    expect(blocks[4].metadata[:align]).to be_nil
  end

  it 'centers subtitles' do
    xml = '<section><subtitle>Interlude</subtitle></section>'
    blocks = described_class.new(xml).parse

    expect(blocks.length).to eq(1)
    expect(blocks.first.type).to eq(:heading)
    expect(blocks.first.metadata[:align]).to eq(:center)
  end
end
