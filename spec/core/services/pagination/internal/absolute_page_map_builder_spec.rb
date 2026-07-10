# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::Pagination::Internal::AbsolutePageMapBuilder do
  def build_document(chapter_lines)
    chapter_class = Struct.new(:lines, keyword_init: true)
    chapters = Array(chapter_lines).map { |lines| chapter_class.new(lines: lines) }

    Class.new do
      def initialize(chapters)
        @chapters = chapters
      end

      def chapter_count
        @chapters.length
      end

      def get_chapter(index)
        @chapters[index]
      end
    end.new(chapters)
  end

  it 'uses text metrics fallback wrapping when wrapper is nil' do
    doc = build_document([['abcdef', '', 'ghij']])
    text_metrics = instance_double(Shoko::Application::Ports::Outbound::TextMetrics)
    allow(text_metrics).to receive(:wrap_plain_text) do |line, width|
      line.to_s.scan(/.{1,#{width}}/)
    end

    map = described_class.build(doc, 3, 2, nil, text_metrics: text_metrics)

    expect(map).to eq([3])
  end

  it 'raises when neither wrapper nor text metrics are provided' do
    doc = build_document([['abc']])

    expect {
      described_class.build(doc, 10, 20)
    }.to raise_error(ArgumentError)
  end
end
