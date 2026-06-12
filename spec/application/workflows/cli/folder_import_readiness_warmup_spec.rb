# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Shoko::Application::Workflows::Cli::FolderImportReadinessWarmup do
  def build_progress_collector
    Struct.new(:events) do
      def update_status(message: nil, progress: nil)
        events << { message: message, progress: progress }
      end
    end.new([])
  end

  let(:page_calculator) do
    instance_double(
      'PageCalculator',
      reset_session!: nil,
      build_dynamic_map!: { total_pages: 42 }
    )
  end
  let(:config) { instance_double('Config', page_numbering_mode: :dynamic) }
  let(:reader_view_state_snapshot) { Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot.build(sidebar_visible: false) }
  let(:app_config_store) { instance_double('AppConfigStore', load: config) }
  let(:reader_view_state_store) { instance_double('ReaderViewStateStore', load: reader_view_state_snapshot) }
  let(:reader_runtime_context) do
    instance_double(
      'ReaderRuntimeContext',
      terminal_size: Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 120, height: 40)
    )
  end
  let(:logger) { instance_double('Logger', debug: nil) }
  let(:document) { instance_double('Document', canonical_path: '/books/a.epub') }

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        page_calculator: page_calculator,
        app_config_store: app_config_store,
        reader_view_state_store: reader_view_state_store,
        reader_runtime_context: reader_runtime_context,
        logger: logger
      )
    )
  end

  it 'builds dynamic pagination for the current terminal layout and resets calculator state around the build' do
    expect(page_calculator).to receive(:reset_session!).ordered
    expect(page_calculator).to receive(:build_dynamic_map!).with(
      120,
      40,
      document,
      config_reader: config,
      sidebar_visible: false
    ).ordered
    expect(page_calculator).to receive(:reset_session!).ordered

    expect(service.warm(document)).to eq(:warmed)
  end

  it 'skips warmup when the current paging mode is not dynamic' do
    allow(config).to receive(:page_numbering_mode).and_return(:absolute)

    expect(page_calculator).to receive(:reset_session!).once
    expect(page_calculator).not_to receive(:build_dynamic_map!)

    expect(service.warm(document)).to eq(:skipped)
  end

  it 'falls back to default terminal dimensions when runtime sizing is unavailable' do
    allow(reader_runtime_context).to receive(:terminal_size)
      .and_return(Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 0, height: 0))

    expect(page_calculator).to receive(:reset_session!).ordered
    expect(page_calculator).to receive(:build_dynamic_map!).with(
      80,
      24,
      document,
      config_reader: config,
      sidebar_visible: false
    ).ordered
    expect(page_calculator).to receive(:reset_session!).ordered

    expect(service.warm(document)).to eq(:warmed)
  end

  it 'logs and returns :error when pagination warmup raises a Shoko error' do
    allow(page_calculator).to receive(:build_dynamic_map!).and_raise(
      Shoko::CacheLoadError.new('/tmp/a.cache', 'boom')
    )

    expect(page_calculator).to receive(:reset_session!).twice
    expect(logger).to receive(:debug).with(
      'cli.folder_import_readiness_warmup.failed',
      error: 'Shoko::CacheLoadError',
      message: 'Cache load failed for /tmp/a.cache: boom',
      path: '/books/a.epub'
    )

    expect(service.warm(document)).to eq(:error)
  end

  it 'reports pagination warmup progress for the CLI presenter' do
    collector = build_progress_collector
    allow(page_calculator).to receive(:build_dynamic_map!) do |_width, _height, _document, config_reader:, sidebar_visible:, &block|
      expect(config_reader).to eq(config)
      expect(sidebar_visible).to be(false)
      block.call(3, 6)
      { total_pages: 42 }
    end

    expect(service.warm(document, progress_reporter: collector)).to eq(:warmed)
    expect(collector.events).to eq(
      [
        { message: 'Warming pagination cache...', progress: 0.0 },
        { message: 'Warming pagination cache (3/6)...', progress: 0.5 },
        { message: 'Pagination cache warmed.', progress: 1.0 },
      ]
    )
  end

  it 'reads sidebar visibility from reader view state instead of the reader session snapshot' do
    allow(reader_view_state_store).to receive(:load)
      .and_return(Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot.build(sidebar_visible: true))

    expect(page_calculator).to receive(:reset_session!).ordered
    expect(page_calculator).to receive(:build_dynamic_map!).with(
      120,
      40,
      document,
      config_reader: config,
      sidebar_visible: true
    ).ordered
    expect(page_calculator).to receive(:reset_session!).ordered

    expect(service.warm(document)).to eq(:warmed)
  end

  it 'warms FB2 documents with empty-line elements through the real import path' do
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => File.join(dir, 'config'), 'XDG_CACHE_HOME' => File.join(dir, 'cache')) do
        file = Tempfile.new(['fb2-empty-line', '.fb2'])
        file.write(<<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
            <description>
              <title-info>
                <book-title>FB2 Empty Line</book-title>
                <author><first-name>Jane</first-name><last-name>Doe</last-name></author>
                <lang>en</lang>
              </title-info>
            </description>
            <body>
              <section>
                <title><p>Chapter 1</p></title>
                <p>Before</p>
                <empty-line/>
                <p>After</p>
              </section>
            </body>
          </FictionBook>
        XML
        file.flush

        container = Shoko::Composition::ContainerFactory.create_default_container
        warmup = Shoko::Composition::ContainerFactory.send(:build_folder_import_document_warmup, container)
        document = container.resolve(:document_loader).load(path: file.path)

        expect(warmup.warm(document)).to eq(:warmed)
      ensure
        file&.close!
      end
    end
  end
end
