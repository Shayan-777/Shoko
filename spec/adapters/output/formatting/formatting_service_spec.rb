# frozen_string_literal: true

require 'json'
require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::FormattingService do
  let(:runtime_config) { Shoko::Adapters::Runtime::NullRuntimeConfig.instance }

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

    service = described_class.new(xhtml_parser_factory: parser_factory, runtime_config: runtime_config)

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
    expect(lines.first).to be_a(Shoko::Application::Ports::Outbound::Formatting::DisplayLine)

    window = service.wrap_window(doc, 0, 20, offset: 0, length: 2, config: double('Config', get: false))
    expect(window.length).to eq(2)
  end

  it 'keeps centered and right-aligned PDF blocks aligned in wrapped output' do
    resolver = lambda do |raw, chapter|
      next unless chapter&.metadata&.dig(:format) == :pdf

      Shoko::Adapters::BookSources::Pdf::PdfContentParser.new(raw)
    end

    service = described_class.new(format_parser_resolver: resolver, runtime_config: runtime_config)
    raw = JSON.generate(
      {
        format: 'pdf-layout-v1',
        lines: [
          { text: '4', x: 150.0, italic: false },
          { break: true },
          { text: 'A right aligned epigraph line.', x: 220.0, italic: true },
          { break: true },
          { text: 'Body paragraph starts here.', x: 72.0, italic: false },
        ],
      }
    )
    chapter = Struct.new(:raw_content, :lines, :blocks, :metadata).new(raw, [], nil, { format: :pdf })
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf')

    lines = service.wrap_all(doc, 0, 40, config: double('Config', get: false))
    texts = lines.map(&:text).reject(&:empty?)

    heading_line = texts.find { |text| text.include?('4') }
    epigraph_line = texts.find { |text| text.include?('A right aligned epigraph line.') }
    body_line = texts.find { |text| text.include?('Body paragraph starts here.') }

    expect(heading_line).to match(/\A\s+4\z/)
    expect(epigraph_line).to match(/\A\s+│\s+A right aligned epigraph line\.\z/)
    expect(body_line).to eq('Body paragraph starts here.')
  end

  it 'formats cached PDF chapters with string metadata keys without leaking raw JSON' do
    fallback_parser = Object.new
    xhtml_factory = lambda do |_raw|
      fallback_parser
    end
    resolver = Shoko::Composition::ContainerFactory.send(
      :build_format_parser_resolver,
      xhtml_factory,
      nil
    )

    service = described_class.new(
      format_parser_resolver: resolver,
      xhtml_parser_factory: xhtml_factory,
      runtime_config: runtime_config
    )
    raw = JSON.generate(
      [
        { text: '4', x: 150.0, italic: false },
        { break: true },
        { text: 'A right aligned epigraph line.', x: 220.0, italic: nil },
        { text: 'PAUL ROBESON', x: 220.0, italic: false },
        { break: true },
        { text: 'Body paragraph starts here.', x: 72.0, italic: false },
      ]
    )
    chapter = Struct.new(:raw_content, :lines, :blocks, :metadata).new(raw, [], nil, { 'format' => 'pdf' })
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf')

    lines = service.wrap_all(doc, 0, 50, config: double('Config', get: false))
    text = lines.map(&:text).join(' ')

    expect(text).to include('A right aligned epigraph line.')
    expect(text).to include('PAUL ROBESON')
    expect(text).not_to include('"text":')
  end

  it 'renders centered PDF attribution signatures as attribution paragraphs, not headings' do
    fallback_parser = Object.new
    xhtml_factory = ->(_raw) { fallback_parser }
    resolver = Shoko::Composition::ContainerFactory.send(
      :build_format_parser_resolver,
      xhtml_factory,
      nil
    )
    service = described_class.new(
      format_parser_resolver: resolver,
      xhtml_parser_factory: xhtml_factory,
      runtime_config: runtime_config
    )

    raw = JSON.generate(
      {
        format: 'pdf-layout-v1',
        lines: [
          { text: '12', x: 150.0, italic: false },
          { break: true },
          { text: 'What is property? Property is theft.', x: 190.0, italic: false },
          { text: 'PIERRE-JOSEPH PROUDHON, 1840', x: 250.0, italic: false },
          { break: true },
          { text: 'The brigand . . . is the true and only revolutionary.', x: 190.0, italic: false },
          { text: 'BAKUNIN, 1870', x: 485.0, italic: false },
          { break: true },
          { text: 'Scoring', x: 150.0, italic: false },
          { break: true },
          { text: 'I first studied law to become a better burglar.', x: 72.0, italic: false },
        ],
      }
    )
    chapter = Struct.new(:raw_content, :lines, :blocks, :metadata).new(raw, [], nil, { 'format' => 'pdf' })
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf')

    lines = service.wrap_all(doc, 0, 80, config: double('Config', get: false))
    attribution_line = lines.find { |line| line.text.include?('PIERRE-JOSEPH PROUDHON, 1840') }
    second_attribution = lines.find { |line| line.text.include?('BAKUNIN, 1870') }

    expect(attribution_line).not_to be_nil
    expect(attribution_line.metadata[:block_type]).to eq(:paragraph)
    expect(attribution_line.metadata[:style]).to eq(:attribution)
    expect(second_attribution).not_to be_nil
    expect(second_attribution.metadata[:block_type]).to eq(:paragraph)
    expect(second_attribution.metadata[:style]).to eq(:attribution)
  end

  it 'keeps mixed-italic body lines in paragraph flow after chapter heading' do
    fallback_parser = Object.new
    xhtml_factory = ->(_raw) { fallback_parser }
    resolver = Shoko::Composition::ContainerFactory.send(
      :build_format_parser_resolver,
      xhtml_factory,
      nil
    )
    service = described_class.new(
      format_parser_resolver: resolver,
      xhtml_parser_factory: xhtml_factory,
      runtime_config: runtime_config
    )

    raw = JSON.generate(
      {
        format: 'pdf-layout-v1',
        lines: [
          { text: '12', x: 150.0, italic: false, italic_ratio: 0.0 },
          { break: true },
          { text: 'What is property? Property is theft.', x: 190.0, italic: true, italic_ratio: 1.0 },
          { text: 'PIERRE-JOSEPH PROUDHON, 1840', x: 250.0, italic: false, italic_ratio: 0.0 },
          { break: true },
          { text: 'Scoring', x: 150.0, italic: false, italic_ratio: 0.0 },
          { break: true },
          { text: 'I first studied law to become a better burglar.', x: 72.0, italic: false, italic_ratio: 0.0 },
          { text: 'studied the California penal code and books like California Criminal', x: 110.0, italic: false, italic_ratio: 0.34 },
          { text: 'Evidence and California Criminal Law by Fricke and Alarcon,', x: 110.0, italic: false, italic_ratio: 0.31 },
          { text: 'concentrating on those areas that were somewhat vague.', x: 72.0, italic: false, italic_ratio: 0.0 },
        ],
      }
    )
    chapter = Struct.new(:raw_content, :lines, :blocks, :metadata).new(raw, [], nil, { 'format' => 'pdf' })
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf')

    lines = service.wrap_all(doc, 0, 80, config: double('Config', get: false))
    studied_line = lines.find { |line| line.text.include?('studied the California penal') }

    expect(studied_line).not_to be_nil
    expect(studied_line.metadata[:block_type]).to eq(:paragraph)
    expect(studied_line.metadata[:style]).to be_nil
  end

  it 'renders mixed-case epigraph attributions as attribution paragraphs' do
    fallback_parser = Object.new
    xhtml_factory = ->(_raw) { fallback_parser }
    resolver = Shoko::Composition::ContainerFactory.send(
      :build_format_parser_resolver,
      xhtml_factory,
      nil
    )
    service = described_class.new(
      format_parser_resolver: resolver,
      xhtml_parser_factory: xhtml_factory,
      runtime_config: runtime_config
    )

    raw = JSON.generate(
      {
        format: 'pdf-layout-v1',
        lines: [
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
        ],
      }
    )
    chapter = Struct.new(:raw_content, :lines, :blocks, :metadata).new(raw, [], nil, { 'format' => 'pdf' })
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf')

    lines = service.wrap_all(doc, 0, 90, config: double('Config', get: false))
    attribution_line = lines.find { |line| line.text.include?('ELLIOT LIEBOW, Tally’s Corner') }
    chapter_heading = lines.find { |line| line.text.include?('The Brothers on the Block') }

    expect(attribution_line).not_to be_nil
    expect(attribution_line.metadata[:block_type]).to eq(:paragraph)
    expect(attribution_line.metadata[:style]).to eq(:attribution)
    expect(chapter_heading).not_to be_nil
    expect(chapter_heading.metadata[:block_type]).to eq(:heading)
  end
end
