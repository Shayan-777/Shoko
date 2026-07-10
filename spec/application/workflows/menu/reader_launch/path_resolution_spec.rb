# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::PathResolution do
  let(:cache_pointer_resolver) { instance_double(Shoko::Application::Ports::Outbound::CachePointerResolver) }
  let(:reader_document_locator) do
    instance_double(
      Shoko::Application::Ports::Outbound::ReaderDocumentLocator,
      canonical_reader_path: '/books/a.epub',
      resolve_source_path: '/books/a.epub',
      document_matches_path?: true
    )
  end
  let(:file_probe) { instance_double(Shoko::Application::Ports::Outbound::FileProbe, exist?: true, file?: true) }

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        cache_pointer_resolver: cache_pointer_resolver,
        reader_document_locator: reader_document_locator,
        file_probe: file_probe,
        logger: nil
      ).validate!
    )
  end

  it 'delegates canonical path and source path resolution' do
    expect(service.canonical_path('/tmp/a.cache')).to eq('/books/a.epub')
    expect(service.canonical_recent_path('/tmp/a.cache')).to eq('/books/a.epub')
  end

  it 'validates cache paths through cache pointer resolver' do
    allow(cache_pointer_resolver).to receive(:cache_pointer?).with('/tmp/a.cache').and_return(true)
    allow(cache_pointer_resolver).to receive(:read_cache).with('/tmp/a.cache', strict: true).and_return({ source_path: '/books/a.epub' })

    expect(service.valid_cache_path?('/tmp/a.cache')).to be(true)
  end
end
