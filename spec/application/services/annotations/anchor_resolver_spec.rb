# frozen_string_literal: true

require 'spec_helper'
require 'shoko/application/services/annotations/anchor_resolver'
require 'shoko/application/services/annotations/chapter_stream_source'
require 'shoko/core/models/document_anchor'

RSpec.describe Shoko::Application::Services::Annotations::AnchorResolver do
  let(:paragraph) do
    'The quick brown fox jumps over the lazy dog while the quick brown cat ' \
      'naps in the warm afternoon sun near the old garden wall'
  end

  def wrap(text, width)
    words = text.split
    lines = ['']
    words.each do |word|
      candidate = lines.last.empty? ? word : "#{lines.last} #{word}"
      if candidate.length <= width
        lines[-1] = candidate
      else
        lines << word
      end
    end
    lines
  end

  def resolver_for(lines, signature: [:sig, lines.hash])
    fetch = Shoko::Application::Services::Annotations::ChapterStreamSource::Fetch.new(
      lines: lines, signature: signature
    )
    source = instance_double(Shoko::Application::Services::Annotations::ChapterStreamSource, fetch: fetch)
    described_class.new(chapter_stream_source: source)
  end

  describe '#resolve' do
    it 'locates a quote and maps it to line-relative char ranges' do
      lines = wrap(paragraph, 30)
      resolver = resolver_for(lines)
      anchor = Shoko::Core::Models::DocumentAnchor.from_h(quote: 'fox jumps over')

      resolution = resolver.resolve(anchor, chapter_index: 0)

      expect(resolution).not_to be_nil
      reassembled = resolution.line_spans.map do |span|
        lines[span.line_offset][span.start_char...span.end_char]
      end.join(' ')
      expect(reassembled.gsub(/\s+/, ' ')).to eq('fox jumps over')
      expect(resolution.start_line_offset).to eq(resolution.line_spans.first.line_offset)
      expect(resolution.line_spans.first.line_text).to eq(lines[resolution.start_line_offset])
    end

    it 'locates the same quote after a re-wrap at a different width' do
      anchor = resolver_for(wrap(paragraph, 30)).capture_quote(quote: 'lazy dog while', chapter_index: 0)

      narrow = wrap(paragraph, 18)
      resolution = resolver_for(narrow).resolve(anchor, chapter_index: 0)

      expect(resolution).not_to be_nil
      text = resolution.line_spans.map { |span| narrow[span.line_offset][span.start_char...span.end_char] }.join(' ')
      expect(text.gsub(/\s+/, ' ')).to eq('lazy dog while')
    end

    it 'matches case-insensitively and across wrap boundaries' do
      lines = wrap(paragraph, 12)
      resolver = resolver_for(lines)
      anchor = Shoko::Core::Models::DocumentAnchor.from_h(quote: 'THE QUICK BROWN FOX')

      resolution = resolver.resolve(anchor, chapter_index: 0)

      expect(resolution).not_to be_nil
      expect(resolution.line_spans.length).to be > 1
    end

    it 'disambiguates repeated quotes by captured context' do
      text = 'alpha beta gamma delta epsilon beta gamma zeta eta theta'
      lines = wrap(text, 14)
      resolver = resolver_for(lines)
      second_line = lines.index { |line| line.include?('zeta') } || (lines.length - 1)

      anchor = resolver.capture_quote(quote: 'beta gamma', chapter_index: 0, line_offset_hint: second_line)
      resolution = resolver.resolve(anchor, chapter_index: 0)

      matched = resolution.line_spans.map { |span| span.line_offset }
      first_occurrence_line = lines.index { |line| line.include?('alpha') }
      expect(anchor.prefix).to end_with('epsilon')
      expect(matched.min).to be > first_occurrence_line
    end

    it 'resolves position-only anchors to a proportional line offset' do
      lines = wrap(paragraph, 20)
      resolver = resolver_for(lines)
      anchor = Shoko::Core::Models::DocumentAnchor.from_h(position: 0.5)

      resolution = resolver.resolve(anchor, chapter_index: 0)

      expect(resolution.start_line_offset).to eq((0.5 * lines.length).round.clamp(0, lines.length - 1))
      expect(resolution.line_spans).to be_empty
    end

    it 'returns nil for empty anchors, unlocatable quotes, and missing streams' do
      lines = wrap(paragraph, 20)
      resolver = resolver_for(lines)

      expect(resolver.resolve(nil, chapter_index: 0)).to be_nil
      expect(resolver.resolve({}, chapter_index: 0)).to be_nil
      missing = Shoko::Core::Models::DocumentAnchor.from_h(quote: 'zebra quantum payload')
      expect(resolver.resolve(missing, chapter_index: 0)).to be_nil

      empty_source = instance_double(Shoko::Application::Services::Annotations::ChapterStreamSource, fetch: nil)
      blind = described_class.new(chapter_stream_source: empty_source)
      expect(blind.resolve({ quote: 'fox' }, chapter_index: 0)).to be_nil
    end

    it 'accepts plain hash anchors with string keys' do
      lines = wrap(paragraph, 30)
      resolver = resolver_for(lines)

      resolution = resolver.resolve({ 'quote' => 'warm afternoon sun' }, chapter_index: 0)

      expect(resolution).not_to be_nil
    end
  end

  describe '#line_offset_for' do
    it 'returns the start line offset for a located quote' do
      lines = wrap(paragraph, 24)
      resolver = resolver_for(lines)

      offset = resolver.line_offset_for({ quote: 'old garden wall' }, chapter_index: 0)

      expect(lines[offset]).to include('old')
    end

    it 'returns nil when nothing locates' do
      resolver = resolver_for(wrap(paragraph, 24))

      expect(resolver.line_offset_for({ quote: 'absent words entirely' }, chapter_index: 0)).to be_nil
    end
  end

  describe '#capture_quote' do
    it 'captures normalized context and a position ratio' do
      lines = wrap(paragraph, 30)
      resolver = resolver_for(lines)

      anchor = resolver.capture_quote(quote: 'lazy dog', chapter_index: 0)

      expect(anchor.quote).to eq('lazy dog')
      expect(anchor.prefix).to end_with('overthe')
      expect(anchor.suffix).to start_with('whilethe')
      expect(anchor.position).to be_between(0.0, 1.0)
    end

    it 'keeps the quote with a coarse position when it cannot be located' do
      resolver = resolver_for(wrap(paragraph, 30))

      anchor = resolver.capture_quote(quote: 'not in the chapter', chapter_index: 0, line_offset_hint: 2)

      expect(anchor.quote).to eq('not in the chapter')
      expect(anchor.prefix).to be_nil
      expect(anchor.position).to be_between(0.0, 1.0)
    end
  end

  describe '#capture_position' do
    it 'captures the line offset as a ratio that survives re-wrapping' do
      wide = wrap(paragraph, 40)
      narrow = wrap(paragraph, 16)

      anchor = resolver_for(wide).capture_position(chapter_index: 0, line_offset: wide.length / 2)
      resolution = resolver_for(narrow).resolve(anchor, chapter_index: 0)

      expect(resolution.start_line_offset).to be_within(1).of(narrow.length / 2)
    end
  end

  describe '#capture_line' do
    it 'captures the line text as a quote anchor that re-locates exactly after a re-wrap' do
      wide = wrap(paragraph, 30)
      narrow = wrap(paragraph, 18)
      target_line = wide.length / 2

      anchor = resolver_for(wide).capture_line(chapter_index: 0, line_offset: target_line)
      offset = resolver_for(narrow).line_offset_for(anchor, chapter_index: 0)

      expect(anchor.quote).to eq(wide[target_line])
      expect(anchor.position).to be_between(0.0, 1.0)
      expect(narrow[offset]).to include(wide[target_line].split.first)
    end

    it 'skips blank lines and captures the first visible text at or after the offset' do
      lines = ['A heading', '', '', 'The body text begins here', 'and continues']
      resolver = resolver_for(lines)

      anchor = resolver.capture_line(chapter_index: 0, line_offset: 1)

      expect(anchor.quote).to eq('The body text begins here')
    end

    it 'falls back to a position-only anchor when the offset is past the chapter text' do
      lines = wrap(paragraph, 30)
      resolver = resolver_for(lines)

      anchor = resolver.capture_line(chapter_index: 0, line_offset: lines.length + 50)

      expect(anchor.quote).to be_nil
      expect(anchor.position).to be_between(0.0, 1.0)
    end

    it 'returns an empty anchor when no stream is available' do
      empty_source = instance_double(Shoko::Application::Services::Annotations::ChapterStreamSource, fetch: nil)
      resolver = described_class.new(chapter_stream_source: empty_source)

      anchor = resolver.capture_line(chapter_index: 0, line_offset: 3)

      expect(anchor).to be_empty
    end
  end
end
