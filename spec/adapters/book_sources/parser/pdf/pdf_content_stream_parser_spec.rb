# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require_relative '../../../../../lib/shoko/adapters/book_sources/pdf/parser/pdf_content_stream_parser'

RSpec.describe Shoko::Adapters::BookSources::Pdf::PdfContentStreamParser do
  it 'sanitizes invalid UTF-8 fragments before style analysis' do
    stream = 'BT /F1 12 Tf 72 700 Td '.b + "(\xFFtext) Tj ET".b

    lines = described_class.new(stream: stream, font_profiles: {}).parse

    expect(lines.length).to eq(1)
    expect(lines.first[:text]).to include('text')
    expect(lines.first[:text].valid_encoding?).to be(true)
  end

  it 'skips inline dictionaries and keeps parsing marked-content text operators' do
    stream = 'BT /Span << /MCID 0 >> BDC /F1 12 Tf 72 700 Td (Visible text) Tj EMC ET'.b

    lines = described_class.new(stream: stream, font_profiles: {}).parse

    expect(lines.map { |line| line[:text] }).to eq(['Visible text'])
  end

  it 'makes progress past a stray closing delimiter instead of looping forever' do
    # A stray '>' with no matching opener used to stall the tokenizer: the
    # operator slice was empty and @pos never advanced, so next_token spun
    # forever. Real marked-content property lists in the wild hit this.
    stream = 'BT /F1 12 Tf 72 700 Td (before) Tj > (after) Tj ET'.b

    lines = Timeout.timeout(5) do
      described_class.new(stream: stream, font_profiles: {}).parse
    end

    text = lines.map { |line| line[:text] }.join(' ')
    expect(text).to include('before').and(include('after'))
  end
end
