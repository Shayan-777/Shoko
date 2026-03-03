# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::RuntimeExecution do
  let(:menu_state_reader) { instance_double('MenuStateReader', current_menu_mode: :browse) }
  let(:state_writer) { instance_double('StateWriter', update_reader_meta: nil, update_reader: nil) }
  let(:reader_launch_state) do
    Shoko::Adapters::Runtime::SessionState::ReaderLaunchStateAdapter.new.tap do |state|
      state.set_preloaded_document(instance_double('Document'))
      state.set_background_worker(instance_double('BackgroundWorker'))
    end
  end
  let(:menu_launch_state) { Shoko::Adapters::Runtime::SessionState::MenuLaunchStateAdapter.new }
  let(:recent_files_repository) { instance_double('RecentFilesRepository', add: nil) }
  let(:catalog) { instance_double('Catalog', update_scan_state: nil) }
  let(:menu_runtime) { instance_double('MenuRuntime', run_reader: nil, switch_mode: nil) }
  let(:path_resolution) do
    instance_double(
      'PathResolution',
      canonical_path: '/books/a.epub',
      canonical_recent_path: '/books/a.epub'
    )
  end
  let(:logger) { instance_double('Logger', debug: nil, error: nil, respond_to?: true) }

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        menu_state_reader: menu_state_reader,
        state_writer: state_writer,
        reader_launch_state: reader_launch_state,
        menu_launch_state: menu_launch_state,
        recent_files_repository: recent_files_repository,
        catalog: catalog,
        menu_runtime: menu_runtime,
        path_resolution: path_resolution,
        logger: logger
      ).validate!
    )
  end

  it 'runs reader and restores menu mode on completion' do
    ensure_callback = ->(_path) { true }
    preloaded_document = reader_launch_state.preloaded_document
    background_worker = reader_launch_state.background_worker

    service.run_reader(path: '/tmp/a.epub', ensure_reader_document_for: ensure_callback)

    expect(state_writer).to have_received(:update_reader_meta).with(book_path: '/books/a.epub', running: true)
    expect(state_writer).to have_received(:update_reader).with(mode: :read)
    expect(menu_runtime).to have_received(:run_reader).with(
      path: '/books/a.epub',
      preloaded_document: preloaded_document,
      background_worker: background_worker
    )
    expect(menu_runtime).to have_received(:switch_mode).with(:browse)
    expect(reader_launch_state.preloaded_document).to be_nil
    expect(reader_launch_state.background_worker).to be_nil
  end
end
