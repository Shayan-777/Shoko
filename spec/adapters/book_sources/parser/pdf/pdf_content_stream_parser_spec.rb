# frozen_string_literal: true

require 'spec_helper'
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
end
