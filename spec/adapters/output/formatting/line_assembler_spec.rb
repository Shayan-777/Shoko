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
    default_runtime_config = Shoko::Adapters::Runtime::NullRuntimeConfig.instance
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
end
