# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::CacheImportAdapter do
  def build_progress_collector
    Struct.new(:events) do
      def update_status(message: nil, progress: nil)
        events << { message: message, progress: progress }
      end
    end.new([])
  end

  let(:document_loader) do
    Class.new do
      include Shoko::Application::Ports::Outbound::DocumentLoader

      def load(path:, progress_reporter: nil); end
    end.new
  end
  let(:document_warmup) do
    Class.new do
      include Shoko::Application::Ports::Outbound::DocumentWarmup

      def warm(document, progress_reporter: nil)
        _ = [document, progress_reporter]
        :warmed
      end
    end.new
  end

  it 'returns :skipped when document is already cached' do
    document = instance_double(Shoko::Application::Models::ReaderDocument, cached?: true)
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil)
                                            .and_return(document)

    adapter = described_class.new(document_loader: document_loader, document_warmup: document_warmup)

    expect(document_warmup).to receive(:warm).with(document, progress_reporter: nil)
    expect(adapter.import('/books/a.epub')).to eq(:skipped)
  end

  it 'returns :imported when document is newly built' do
    document = instance_double(Shoko::Application::Models::ReaderDocument, cached?: false)
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil)
                                            .and_return(document)

    adapter = described_class.new(document_loader: document_loader, document_warmup: document_warmup)

    expect(document_warmup).to receive(:warm).with(document, progress_reporter: nil)
    expect(adapter.import('/books/a.epub')).to eq(:imported)
  end

  it 'rejects a warmup collaborator that does not implement the DocumentWarmup port' do
    expect do
      described_class.new(document_loader: document_loader, document_warmup: Object.new)
    end.to raise_error(ArgumentError, /DocumentWarmup/)
  end

  it 'supports import without a warmup collaborator' do
    document = instance_double(Shoko::Application::Models::ReaderDocument, cached?: false)
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil)
                                            .and_return(document)

    adapter = described_class.new(document_loader: document_loader)

    expect(adapter.import('/books/a.epub')).to eq(:imported)
  end

  it 'warms imported documents with reader view state during the batch import path' do
    document = instance_double(Shoko::Application::Models::ReaderDocument, cached?: false, canonical_path: '/books/a.epub')
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil)
                                            .and_return(document)
    page_calculator = instance_double(Shoko::Application::Services::Pagination::PageCalculatorService, reset_session!: nil, build_dynamic_map!: { total_pages: 42 })
    warmup = Shoko::Application::Workflows::Cli::FolderImportReadinessWarmup.new(
      deps: Shoko::Application::Workflows::Cli::FolderImportReadinessWarmup::Dependencies.new(
        page_calculator: page_calculator,
        app_config_store: instance_double(Shoko::Application::Ports::Outbound::AppConfigStore, load: instance_double(Shoko::Application::Ports::Outbound::State::ConfigSnapshot, page_numbering_mode: :dynamic)),
        reader_view_state_store: instance_double(
          Shoko::Application::Ports::Outbound::ReaderViewStateStore,
          load: Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot.build
        ),
        reader_runtime_context: instance_double(
          Shoko::Application::Ports::Outbound::ReaderRuntimeContext,
          terminal_size: Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 90, height: 32)
        ),
        logger: instance_double(Shoko::Application::Ports::Outbound::Logging, debug: nil)
      )
    )
    adapter = described_class.new(document_loader: document_loader, document_warmup: warmup)

    expect(page_calculator).to receive(:build_dynamic_map!).with(
      90,
      32,
      document,
      config_reader: have_attributes(page_numbering_mode: :dynamic)
    )

    expect(adapter.import('/books/a.epub')).to eq(:imported)
  end

  it 'forwards progress through load and warmup stages without regressing overall progress' do
    collector = build_progress_collector
    document = instance_double(Shoko::Application::Models::ReaderDocument, cached?: false)
    loader = Class.new do
      include Shoko::Application::Ports::Outbound::DocumentLoader

      attr_reader :reporters

      def initialize(document)
        @document = document
        @reporters = []
      end

      def load(path: nil, progress_reporter: nil)
        _ = path
        @reporters << progress_reporter
        progress_reporter&.update_status(message: 'Loading cache...', progress: 0.5)
        @document
      end
    end.new(document)
    warmup = Class.new do
      include Shoko::Application::Ports::Outbound::DocumentWarmup

      attr_reader :reporters

      def initialize
        @reporters = []
      end

      def warm(document, progress_reporter: nil)
        @reporters << [document, progress_reporter]
        progress_reporter&.update_status(message: 'Warming pagination cache...', progress: 0.5)
        :warmed
      end
    end.new
    adapter = described_class.new(document_loader: loader, document_warmup: warmup)

    expect(adapter.import('/books/a.epub', progress_reporter: collector)).to eq(:imported)
    expect(loader.reporters.first).not_to be_nil
    expect(warmup.reporters.first.first).to eq(document)
    expect(warmup.reporters.first.last).not_to be_nil
    expect(collector.events).to eq(
      [
        { message: 'Loading cache...', progress: 0.425 },
        { message: 'Warming pagination cache...', progress: 0.925 },
        { message: 'Imported a.epub', progress: 1.0 },
      ]
    )
  end

  it 'raises a file-scoped parse error when the document loader returns nil' do
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil)
                                            .and_return(nil)

    adapter = described_class.new(document_loader: document_loader)

    expect { adapter.import('/books/a.epub') }
      .to raise_error(Shoko::BookParseError, 'Malformed book input at /books/a.epub: document import returned nil')
  end

  it 'propagates BookParseError when the document service raises malformed-book input' do
    allow(document_loader).to receive(:load).with(path: '/books/bad.epub', progress_reporter: nil)
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
