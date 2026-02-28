# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::DocumentPreparation do
  let(:reader_session_context) { Shoko::Bootstrap::ReaderSessionContext.new }
  let(:state_writer) { instance_double('StateWriter', update_pagination_state: nil) }
  let(:logger) { instance_double('Logger', debug: nil) }
  let(:loaded_document) { instance_double('Document', chapter_count: 7, canonical_path: '/books/a.epub') }
  let(:document_loader) { instance_double('DocumentService', load_document: loaded_document) }
  let(:document_service_factory) { instance_double('DocumentServiceFactory') }
  let(:background_worker_factory) { nil }
  let(:path_resolution) do
    instance_double(
      'PathResolution',
      canonical_path: '/books/a.epub',
      document_matches?: false,
      cache_pointer?: false
    )
  end

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        document_service_factory: document_service_factory,
        reader_session_context: reader_session_context,
        state_writer: state_writer,
        background_worker_factory: background_worker_factory,
        logger: logger
      ).validate!
    )
  end

  it 'loads and registers reader document when canonical path differs' do
    allow(document_service_factory).to receive(:call)
      .with('/books/a.epub', progress_reporter: nil, background_worker: nil)
      .and_return(document_loader)

    result = service.ensure_reader_document_for(
      path: '/tmp/a.epub',
      path_resolution: path_resolution,
      on_error: nil
    )

    expect(result).to be(true)
    expect(reader_session_context.document).to eq(loaded_document)
    expect(state_writer).to have_received(:update_pagination_state).with(total_chapters: 7)
  end

  it 'reuses current document when canonical path already matches' do
    reader_session_context.document = loaded_document
    allow(path_resolution).to receive(:document_matches?).with(loaded_document, '/books/a.epub').and_return(true)
    allow(document_service_factory).to receive(:call)

    result = service.ensure_reader_document_for(
      path: '/tmp/a.epub',
      path_resolution: path_resolution,
      on_error: nil
    )

    expect(result).to be(true)
    expect(document_service_factory).not_to have_received(:call)
  end
end
