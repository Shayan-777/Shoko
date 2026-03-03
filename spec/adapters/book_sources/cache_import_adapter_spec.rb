# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::CacheImportAdapter do
  let(:factory) { instance_double('DocumentServiceFactory') }

  it 'returns :skipped when document is already cached' do
    service = instance_double('DocumentService')
    document = instance_double('Document', cached?: true)
    allow(factory).to receive(:call).with('/books/a.epub', progress_reporter: nil, background_worker: nil)
                                   .and_return(service)
    allow(service).to receive(:load_document).and_return(document)

    adapter = described_class.new(document_service_factory: factory)

    expect(adapter.import('/books/a.epub')).to eq(:skipped)
  end

  it 'returns :imported when document is newly built' do
    service = instance_double('DocumentService')
    document = instance_double('Document', cached?: false)
    allow(factory).to receive(:call).with('/books/a.epub', progress_reporter: nil, background_worker: nil)
                                   .and_return(service)
    allow(service).to receive(:load_document).and_return(document)

    adapter = described_class.new(document_service_factory: factory)

    expect(adapter.import('/books/a.epub')).to eq(:imported)
  end

  it 'raises ImportError when the document service raises BookParseError' do
    service = instance_double('DocumentService')
    allow(factory).to receive(:call).with('/books/bad.epub', progress_reporter: nil, background_worker: nil)
                                   .and_return(service)
    allow(service).to receive(:load_document).and_raise(Shoko::BookParseError.new('bad book', '/books/bad.epub'))

    adapter = described_class.new(document_service_factory: factory)

    expect { adapter.import('/books/bad.epub') }
      .to raise_error(Shoko::Adapters::BookSources::CacheImportAdapter::ImportError, /bad book/)
  end

  it 'propagates importer failures for workflow-level aggregation' do
    allow(factory).to receive(:call).and_raise(StandardError, 'boom')

    adapter = described_class.new(document_service_factory: factory)

    expect { adapter.import('/books/a.epub') }.to raise_error(StandardError, 'boom')
  end
end
