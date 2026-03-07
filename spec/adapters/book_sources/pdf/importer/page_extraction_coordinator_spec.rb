# frozen_string_literal: true

require 'json'
require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Pdf::Importer::PageExtractionCoordinator do
  let(:extractor) { instance_double('PdfTextExtractor') }

  it 'normalizes invalid layout text to UTF-8 before generating the layout payload' do
    allow(extractor).to receive(:extract_page_layout).with(:page1).and_return(
      [
        { text: "Lenin\x92s".b, x: 12.5, italic: false, italic_ratio: 0.0 }
      ]
    )

    coordinator = described_class.new(pages: [:page1], extractor: extractor, file_path: '/books/bad.pdf')
    payload = coordinator.extract_text(start_page: 0, end_page: 0)
    parsed = JSON.parse(payload)

    expect(parsed['format']).to eq('pdf-layout-v1')
    expect(parsed['lines'].first['text']).to eq("Lenin\uFFFDs")
  end

  it 'raises a single file-scoped malformed-book error when layout payload generation fails' do
    allow(extractor).to receive(:extract_page_layout).with(:page1).and_return(
      [
        { text: 'content', x: 1 }
      ]
    )
    allow(JSON).to receive(:generate).and_raise(JSON::GeneratorError, 'bad payload')

    coordinator = described_class.new(pages: [:page1], extractor: extractor, file_path: '/books/bad.pdf')

    expect { coordinator.extract_text(start_page: 0, end_page: 0) }
      .to raise_error(
        Shoko::MalformedBookInputError,
        'Malformed book input at /books/bad.pdf: failed to build PDF layout payload: bad payload'
      )
  end
end
