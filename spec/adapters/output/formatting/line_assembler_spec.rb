# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::FormattingService::LineAssembler do
  let(:tokenizer) { described_class::Tokenizer }
  let(:runtime_config) do
    instance_double(
      'RuntimeConfig',
      line_assembler_tokenize_cache_disabled?: false,
      line_assembler_token_width_hints_disabled?: false,
      text_metrics_cache_disabled?: false,
      text_metrics_ascii_fast_path_disabled?: false,
      wrap_plain_text_cache_disabled?: false
    )
  end

  before do
    tokenizer.configure_runtime_config!(runtime_config: runtime_config)
    Shoko::Shared::Terminal::TextMetrics.configure_runtime_config!(runtime_config: runtime_config)
  end

  after do
    default_runtime_config = Shoko::Adapters::Output::Terminal::NullRuntimeConfig.instance
    tokenizer.configure_runtime_config!(runtime_config: default_runtime_config)
    Shoko::Shared::Terminal::TextMetrics.configure_runtime_config!(runtime_config: default_runtime_config)
  end

  it 'tokenizes newlines into explicit newline tokens' do
    segments = [Shoko::Core::Models::TextSegment.new(text: "a\nb")]
    tokens = tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: ->(_src) { false })
    expect(tokens.any? { |t| t[:newline] }).to be(true)
  end

  it 'returns the same tokens with tokenize cache enabled and disabled' do
    segments = [Shoko::Core::Models::TextSegment.new(text: ('alpha beta gamma ' * 8), styles: { bold: true })]
    renderable = ->(_src) { false }

    baseline = tokenizer.with_tokenize_cache(enabled: false) do
      tokenizer.clear_tokenize_cache
      tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: renderable)
    end

    optimized = tokenizer.with_tokenize_cache(enabled: true) do
      tokenizer.clear_tokenize_cache
      tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: renderable)
    end

    expect(optimized).to eq(baseline)
  end

  it 'reuses frozen tokenized output when tokenize cache is enabled' do
    segments = [Shoko::Core::Models::TextSegment.new(text: 'one two three four', styles: { italic: true })]
    renderable = ->(_src) { false }

    tokenizer.with_tokenize_cache(enabled: true) do
      tokenizer.clear_tokenize_cache
      first = tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: renderable)
      second = tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: renderable)

      expect(second.object_id).to eq(first.object_id)
      expect(first).to be_frozen
      expect(first.first).to be_frozen
    end
  end

  it 'produces identical wrapped output with token width hints enabled and disabled' do
    segments = [Shoko::Core::Models::TextSegment.new(text: ('alpha beta gamma delta ' * 6), styles: { bold: true })]
    renderable = ->(_src) { false }
    wrapper = described_class::TextWrapper.new(14, image_builder: double('ImageBuilder'))

    tokens_without_hints = tokenizer.with_tokenize_cache(enabled: false) do
      tokenizer.with_token_width_hints(enabled: false) do
        tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: renderable)
      end
    end

    tokens_with_hints = tokenizer.with_tokenize_cache(enabled: false) do
      tokenizer.with_token_width_hints(enabled: true) do
        tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: renderable)
      end
    end

    lines_without_hints = wrapper.wrap(tokens_without_hints, metadata: {}, prefix: nil, continuation_prefix: nil)
    lines_with_hints = wrapper.wrap(tokens_with_hints, metadata: {}, prefix: nil, continuation_prefix: nil)

    expect(lines_with_hints.map(&:text)).to eq(lines_without_hints.map(&:text))
    expect(lines_with_hints.map { |line| line.segments.map(&:text) })
      .to eq(lines_without_hints.map { |line| line.segments.map(&:text) })
  end

  it 'creates image tokens when inline image rendering is enabled' do
    segments = [Shoko::Core::Models::TextSegment.new(text: 'img', styles: { inline_image: { src: 'x' } })]
    tokens = tokenizer.tokenize(segments, image_rendering: true, renderable_image_src: ->(_src) { true })
    expect(tokens.any? { |t| t[:image] }).to be(true)
  end

  it 'wraps lines with list prefixes and continuation indentation' do
    segments = [Shoko::Core::Models::TextSegment.new(text: 'one two three four')]
    tokens = tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: ->(_src) { false })
    wrapper = described_class::TextWrapper.new(10, image_builder: double('ImageBuilder'))

    lines = wrapper.wrap(tokens, metadata: {}, prefix: '* ', continuation_prefix: nil)

    expect(lines.length).to be > 1
    expect(lines.first.text).to start_with('* ')
    expect(lines[1].text).to start_with('  ')
  end

  it 'splits oversized tokens so lines stay within width constraints' do
    word = 'supercalifragilisticexpialidocious'
    segments = [Shoko::Core::Models::TextSegment.new(text: word, styles: { italic: true })]
    tokens = tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: ->(_src) { false })
    wrapper = described_class::TextWrapper.new(10, image_builder: double('ImageBuilder'))

    lines = wrapper.wrap(tokens, metadata: {}, prefix: nil, continuation_prefix: nil)

    expect(lines.length).to be > 1
    expect(lines.map(&:text).join).to eq(word)
    expect(lines.all? do |line|
      Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(line.text) <= 10
    end).to be(true)
    expect(lines.all? do |line|
      line.segments.all? { |segment| segment.styles[:italic] }
    end).to be(true)
  end

  it 'splits tokens that overflow list continuation width' do
    token_text = '123456789'
    segments = [Shoko::Core::Models::TextSegment.new(text: token_text)]
    tokens = tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: ->(_src) { false })
    wrapper = described_class::TextWrapper.new(10, image_builder: double('ImageBuilder'))

    lines = wrapper.wrap(tokens, metadata: {}, prefix: '* ', continuation_prefix: nil)
    content = lines.map.with_index do |line, index|
      line.text.sub(index.zero? ? /^\* / : /^  /, '')
    end.join

    expect(lines.length).to be > 1
    expect(content).to eq(token_text)
    expect(lines.all? do |line|
      Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(line.text) <= 10
    end).to be(true)
  end

  it 'renders table blocks using box drawing glyphs' do
    table_data = {
      rows: [
        {
          header: true,
          cells: [
            { text: 'Header A', header: true, colspan: 1, rowspan: 1 },
            { text: 'Header B', header: true, colspan: 1, rowspan: 1 },
          ],
        },
        {
          header: false,
          cells: [
            { text: 'Cell 1', header: false, colspan: 1, rowspan: 1 },
            { text: 'Cell 2', header: false, colspan: 1, rowspan: 1 },
          ],
        },
      ],
    }

    block = Shoko::Core::Models::ContentBlock.new(
      type: :table,
      segments: [Shoko::Core::Models::TextSegment.new(text: "Header A | Header B\nCell 1 | Cell 2")],
      metadata: { table: table_data }
    )

    assembler = described_class.new(40)
    lines = assembler.build([block])
    table_lines = lines.map(&:text).reject(&:empty?)

    expect(table_lines.first).to start_with('┌')
    expect(table_lines.first).to end_with('┐')
    expect(table_lines.any? { |line| line.include?('│') }).to be(true)
    expect(table_lines.any? { |line| line.include?('┼') }).to be(true)
    expect(table_lines.last).to start_with('└')
    expect(table_lines.last).to end_with('┘')
  end

  it 'applies center alignment to paragraph lines' do
    block = Shoko::Core::Models::ContentBlock.new(
      type: :paragraph,
      segments: [Shoko::Core::Models::TextSegment.new(text: 'Hi')],
      metadata: { align: :center }
    )

    assembler = described_class.new(10)
    lines = assembler.build([block])
    first = lines.first

    expect(first.text).to start_with('    Hi')
  end

  it 'treats legacy blockquote blocks as quote blocks during wrapping' do
    block = Shoko::Core::Models::ContentBlock.new(
      type: :blockquote,
      segments: [Shoko::Core::Models::TextSegment.new(text: 'Legacy quote')]
    )

    assembler = described_class.new(40)
    lines = assembler.build([block])
    first = lines.first

    expect(first.text).to start_with('│ ')
    expect(first.metadata[:block_type]).to eq(:quote)
  end

  it 'keeps multiline centered quote bars vertically aligned' do
    block = Shoko::Core::Models::ContentBlock.new(
      type: :quote,
      segments: [
        Shoko::Core::Models::TextSegment.new(
          text: 'In my case I worked hard from sunup until sundown trying to make a living for my family.'
        )
      ],
      metadata: { align: :center }
    )

    assembler = described_class.new(60)
    lines = assembler.build([block])
    quote_lines = lines.select { |line| line.metadata[:block_type] == :quote }
    quote_columns = quote_lines.map { |line| line.text.index('│') }

    expect(quote_lines.length).to be > 1
    expect(quote_columns.compact.uniq.length).to eq(1)
  end

  def paragraph(text, metadata = {})
    Shoko::Core::Models::ContentBlock.new(
      type: :paragraph,
      segments: [Shoko::Core::Models::TextSegment.new(text: text)],
      metadata: metadata
    )
  end

  it 'honors spacing buckets between blocks' do
    tight = [paragraph('One.', { spacing_after: 0 }), paragraph('Two.', { spacing_before: 0 })]
    airy = [paragraph('One.', { spacing_after: 2 }), paragraph('Two.')]

    tight_lines = described_class.new(40).build(tight)
    airy_lines = described_class.new(40).build(airy)

    expect(tight_lines.map(&:text)).to eq(['One.', 'Two.'])
    expect(airy_lines.map(&:text)).to eq(['One.', '', '', 'Two.'])
  end

  it 'keeps the classic single blank line for blocks without spacing metadata' do
    lines = described_class.new(40).build([paragraph('One.'), paragraph('Two.')])

    expect(lines.map(&:text)).to eq(['One.', '', 'Two.'])
  end

  it 'applies first-line and left indents from block metadata' do
    block = paragraph(
      'A paragraph long enough to wrap across two rendered lines of output text here.',
      { first_line_indent: 2, indent_left: 3 }
    )

    lines = described_class.new(40).build([block])

    expect(lines.first.text).to start_with('     A')
    expect(lines[1].text).to start_with('   ')
    expect(lines[1].text).not_to start_with('    ')
  end

  it 'centers chapter-level headings by default but honors explicit alignment' do
    centered = Shoko::Core::Models::ContentBlock.new(
      type: :heading, level: 2,
      segments: [Shoko::Core::Models::TextSegment.new(text: 'Title')], metadata: { level: 2 }
    )
    lefted = Shoko::Core::Models::ContentBlock.new(
      type: :heading, level: 2,
      segments: [Shoko::Core::Models::TextSegment.new(text: 'Title')], metadata: { level: 2, align: :left }
    )

    centered_lines = described_class.new(41).build([centered])
    lefted_lines = described_class.new(41).build([lefted])

    expect(centered_lines.first.text).to eq("#{' ' * 18}Title")
    expect(lefted_lines.first.text).to eq('Title')
  end

  it 'gives headings extra room above by default' do
    lines = described_class.new(40).build([
                                            paragraph('Prose.'),
                                            Shoko::Core::Models::ContentBlock.new(
                                              type: :heading, level: 2,
                                              segments: [Shoko::Core::Models::TextSegment.new(text: 'Next')],
                                              metadata: { level: 2 }
                                            ),
                                          ])

    expect(lines.map(&:text)[0, 3]).to eq(['Prose.', '', ''])
  end

  it 'frames consecutive boxed blocks with borders' do
    blocks = [
      paragraph('Inside the box.', { box_group: 1, spacing_after: 0 }),
      paragraph('Still inside.', { box_group: 1, spacing_before: 0 }),
    ]

    lines = described_class.new(40).build(blocks)

    expect(lines.first.text).to start_with('┌')
    expect(lines.last.text).to start_with('└')
    expect(lines[1].text).to start_with('│ Inside the box.')
    expect(lines[1].text).to end_with('│')
  end

  it 'keeps verse blocks tight with a hanging indent' do
    verse = [
      paragraph('A verse line long enough that it wraps onto a second line for sure here', { role: :verse }),
      paragraph('Second verse line', { role: :verse }),
    ]

    lines = described_class.new(40).build(verse)

    expect(lines.map(&:text)).not_to include('')
    expect(lines[1].text).to start_with('  ')
  end

  it 'centers and dims scene breaks' do
    lines = described_class.new(40).build([paragraph('One.'), paragraph('* * *'), paragraph('Two.')])
    break_line = lines.find { |line| line.text.include?('* * *') }

    expect(break_line.text.strip).to eq('* * *')
    expect(break_line.text).to start_with(' ')
    expect(break_line.segments.any? { |segment| segment.styles[:dim] }).to be(true)
  end

  describe 'typography preferences' do
    let(:book_styled) do
      [
        paragraph('First paragraph.', { spacing_after: 0, first_line_indent: 2 }),
        paragraph('Second paragraph.', { spacing_before: 0, first_line_indent: 2 }),
      ]
    end

    it 'forces classic spaced paragraphs in :spaced mode' do
      lines = described_class.new(40, typography: { paragraph_style: :spaced }).build(book_styled)

      expect(lines.map(&:text)).to eq(['First paragraph.', '', 'Second paragraph.'])
    end

    it 'forces tight indented paragraphs in :indent mode' do
      plain = [paragraph('First paragraph.'), paragraph('Second paragraph.')]
      lines = described_class.new(40, typography: { paragraph_style: :indent }).build(plain)

      expect(lines.map(&:text)).to eq(['  First paragraph.', '  Second paragraph.'])
    end

    it 'justifies plain paragraphs when justify is on' do
      block = paragraph('alpha beta gamma delta epsilon zeta eta theta iota kappa')
      lines = described_class.new(24, typography: { justify: :on }).build([block])

      expect(lines[0].text.length).to eq(24)
      expect(lines[0].text).to match(/alpha\s{2,}beta|beta\s{2,}gamma|gamma\s{2,}delta/)
    end

    it 'suppresses book-requested justification when justify is off' do
      block = paragraph('alpha beta gamma delta epsilon zeta eta theta iota kappa', { align: :justify })
      lines = described_class.new(24, typography: { justify: :off }).build([block])

      expect(lines[0].text).not_to match(/\s{2}/)
    end
  end
end
