# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::CacheImportAdapter do
  let(:document_loader) do
    Class.new do
      include Shoko::Core::Ports::Outbound::DocumentLoader

      def load(path:, progress_reporter: nil, background_worker: nil)
      end
    end.new
  end

  it 'returns :skipped when document is already cached' do
    document = instance_double('Document', cached?: true)
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil, background_worker: nil)
                                     .and_return(document)

    adapter = described_class.new(document_loader: document_loader)

    expect(adapter.import('/books/a.epub')).to eq(:skipped)
  end

  it 'returns :imported when document is newly built' do
    document = instance_double('Document', cached?: false)
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil, background_worker: nil)
                                     .and_return(document)

    adapter = described_class.new(document_loader: document_loader)

    expect(adapter.import('/books/a.epub')).to eq(:imported)
  end

  it 'propagates BookParseError when the document service raises malformed-book input' do
    allow(document_loader).to receive(:load).with(path: '/books/bad.epub', progress_reporter: nil, background_worker: nil)
                                     .and_raise(Shoko::BookParseError.new('bad book', '/books/bad.epub'))

    adapter = described_class.new(document_loader: document_loader)

    expect { adapter.import('/books/bad.epub') }
      .to raise_error(Shoko::BookParseError, /bad book/)
  end

  it 'propagates importer failures for workflow-level aggregation' do
    allow(document_loader).to receive(:load).and_raise(StandardError, 'boom')

    adapter = described_class.new(document_loader: document_loader)

    expect { adapter.import('/books/a.epub') }.to raise_error(StandardError, 'boom')
  end
end
