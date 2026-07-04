# frozen_string_literal: true

require 'json'
require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::FormattingService do
  let(:runtime_config) { Shoko::Adapters::Output::Terminal::NullRuntimeConfig.instance }

  # Wrapping consults KittyGraphics.supported?, which probes the real terminal
  # ($TERM / $KITTY_WINDOW_ID). Pin it false so these layout specs are hermetic
  # — the text path is what they assert. The image path (and the config
  # contract it reads) is covered explicitly in the
  # "when the terminal supports kitty graphics" context below.
  before do
    allow(Shoko::Adapters::Output::Kitty::KittyGraphics).to receive(:supported?).and_return(false)
  end

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
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.epub', metadata: {})

    lines = service.wrap_all(doc, 0, 20, config: double('Config', get: false), lines_per_page: 10)
    expect(lines).not_to be_empty
    expect(lines.first).to be_a(Shoko::Application::Ports::Outbound::Formatting::DisplayLine)

    window = service.wrap_window(doc, 0, 20, offset: 0, length: 2, config: double('Config', get: false))
    expect(window.length).to eq(2)
  end

  it 'serves identical wrapped lines under concurrent UI-thread and worker access' do
    parser_factory = lambda do |raw|
      Class.new do
        define_method(:parse) do
          [Shoko::Core::Models::ContentBlock.new(
            type: :paragraph,
            segments: [Shoko::Core::Models::TextSegment.new(text: raw.to_s * 3)]
          )]
        end
      end.new
    end

    service = described_class.new(xhtml_parser_factory: parser_factory, runtime_config: runtime_config)

    chapter_struct = Struct.new(:raw_content, :lines, :blocks, :metadata)
    chapters = Array.new(8) { |i| chapter_struct.new("chapter #{i} words repeat here", [], nil, {}) }
    doc = double('Doc', canonical_path: '/tmp/threaded.epub', metadata: {})
    allow(doc).to receive(:get_chapter) { |i| chapters[i] }

    config = double('Config', get: false)
    expected = Array.new(8) { |i| service.wrap_all(doc, i, 24, config: config).map(&:text) }

    mismatches = Queue.new
    threads = Array.new(2) do |worker_index|
      Thread.new do
        40.times do |step|
          index = (step + worker_index) % 8
          texts = service.wrap_all(doc, index, 24, config: config).map(&:text)
          mismatches << [index, texts] unless texts == expected[index]
          service.wrap_window(doc, index, 24, offset: 0, length: 2, config: config)
        end
      end
    end
    threads.each(&:join)

    expect(mismatches.size).to eq(0)
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
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf', metadata: {})

    lines = service.wrap_all(doc, 0, 40, config: double('Config', get: false))
    texts = lines.map(&:text).reject(&:empty?)

    heading_line = texts.find { |text| text.include?('4') }
    epigraph_line = texts.find { |text| text.include?('A right aligned epigraph line.') }
    body_line = texts.find { |text| text.include?('Body paragraph starts here.') }

    expect(heading_line).to match(/\A\s+4\z/)
    # Epigraphs render as plain italic text shifted to their alignment — the
    # quote gutter bar is reserved for quoted prose.
    expect(epigraph_line).to match(/\A\s+A right aligned epigraph line\.\z/)
    expect(epigraph_line).not_to include('│')
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
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf', metadata: {})

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
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf', metadata: {})

    lines = service.wrap_all(doc, 0, 80, config: double('Config', get: false))
    attribution_line = lines.find { |line| line.text.include?('PIERRE-JOSEPH PROUDHON, 1840') }
    second_attribution = lines.find { |line| line.text.include?('BAKUNIN, 1870') }

    expect(attribution_line).not_to be_nil
    expect(attribution_line.metadata[:block_type]).to eq(:paragraph)
    expect(attribution_line.metadata[:role]).to eq(:attribution)
    expect(second_attribution).not_to be_nil
    expect(second_attribution.metadata[:block_type]).to eq(:paragraph)
    expect(second_attribution.metadata[:role]).to eq(:attribution)
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
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf', metadata: {})

    lines = service.wrap_all(doc, 0, 80, config: double('Config', get: false))
    studied_line = lines.find { |line| line.text.include?('studied the California penal') }

    expect(studied_line).not_to be_nil
    expect(studied_line.metadata[:block_type]).to eq(:paragraph)
    expect(studied_line.metadata[:role]).to be_nil
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
    doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.pdf', metadata: {})

    lines = service.wrap_all(doc, 0, 90, config: double('Config', get: false))
    attribution_line = lines.find { |line| line.text.include?('ELLIOT LIEBOW, Tally’s Corner') }
    chapter_heading = lines.find { |line| line.text.include?('The Brothers on the Block') }

    expect(attribution_line).not_to be_nil
    expect(attribution_line.metadata[:block_type]).to eq(:paragraph)
    expect(attribution_line.metadata[:role]).to eq(:attribution)
    expect(chapter_heading).not_to be_nil
    expect(chapter_heading.metadata[:block_type]).to eq(:heading)
  end

  context 'when the terminal supports kitty graphics' do
    before do
      allow(Shoko::Adapters::Output::Kitty::KittyGraphics).to receive(:supported?).and_return(true)
    end

    # Regression guard for the kitty_images contract: wrapping reads image
    # enablement off the injected config. A config that does not expose
    # #kitty_images must degrade to the text path, never raise NoMethodError
    # up into the reader's render loop.
    it 'degrades to the text path without raising when the config lacks #kitty_images' do
      blocks = [Shoko::Core::Models::ContentBlock.new(
        type: :paragraph, segments: [Shoko::Core::Models::TextSegment.new(text: 'Hello world')]
      )]
      parser_factory = ->(_raw) { Class.new { define_method(:parse) { blocks } }.new }
      service = described_class.new(xhtml_parser_factory: parser_factory, runtime_config: runtime_config)
      chapter = Struct.new(:raw_content, :lines, :blocks, :metadata).new(
        '<p>raw</p>', [], nil, { source_path: '/tmp/book.epub' }
      )
      doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.epub', metadata: {})

      lines = nil
      expect { lines = service.wrap_all(doc, 0, 20, config: double('Config', get: false)) }.not_to raise_error
      expect(lines).not_to be_empty
    end

    it 'honors an explicit kitty_images flag exposed by the config' do
      blocks = [Shoko::Core::Models::ContentBlock.new(
        type: :paragraph, segments: [Shoko::Core::Models::TextSegment.new(text: 'Hello world')]
      )]
      parser_factory = ->(_raw) { Class.new { define_method(:parse) { blocks } }.new }
      service = described_class.new(xhtml_parser_factory: parser_factory, runtime_config: runtime_config)
      chapter = Struct.new(:raw_content, :lines, :blocks, :metadata).new(
        '<p>raw</p>', [], nil, { source_path: '/tmp/book.epub' }
      )
      doc = double('Doc', get_chapter: chapter, canonical_path: '/tmp/book.epub', metadata: {})
      config = Struct.new(:kitty_images).new(false)

      expect(service.wrap_all(doc, 0, 20, config: config)).not_to be_empty
    end
  end
end
