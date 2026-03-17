# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Cli::FolderImportReadinessWarmup do
  let(:page_calculator) do
    instance_double(
      'PageCalculator',
      reset_session!: nil,
      build_dynamic_map!: { total_pages: 42 }
    )
  end
  let(:config) { instance_double('Config', page_numbering_mode: :dynamic) }
  let(:reader_snapshot) { instance_double('ReaderSnapshot', sidebar_visible?: false) }
  let(:app_config_store) { instance_double('AppConfigStore', load: config) }
  let(:reader_session_store) { instance_double('ReaderSessionStore', load: reader_snapshot) }
  let(:reader_runtime_context) do
    instance_double(
      'ReaderRuntimeContext',
      terminal_size: Shoko::Core::Models::Session::TerminalSize.build(width: 120, height: 40)
    )
  end
  let(:logger) { instance_double('Logger', debug: nil) }
  let(:document) { instance_double('Document', canonical_path: '/books/a.epub') }

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        page_calculator: page_calculator,
        app_config_store: app_config_store,
        reader_session_store: reader_session_store,
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
      .and_return(Shoko::Core::Models::Session::TerminalSize.build(width: 0, height: 0))

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
end
