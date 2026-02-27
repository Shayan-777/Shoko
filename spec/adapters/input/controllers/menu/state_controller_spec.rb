# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::StateController do
  let(:catalog) { instance_double('Catalog', start_scan: nil) }
  let(:terminal_service) { instance_double('TerminalService') }
  let(:menu) do
    instance_double(
      'MenuController',
      catalog: catalog,
      terminal_service: terminal_service,
      draw_screen: nil,
      switch_to_mode: nil,
      filtered_epubs: []
    )
  end
  let(:pagination_orchestrator) { instance_double('PaginationOrchestrator') }
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }
  let(:reader_session_context) { Shoko::Bootstrap::ReaderSessionContext.new }
  let(:menu_session_context) { Shoko::Bootstrap::MenuSessionContext.new }
  let(:menu_state_reader) { instance_double('MenuStateReader') }
  let(:menu_state_writer) { instance_double('MenuStateWriter') }
  let(:state_writer) { instance_double('StateWriter') }
  let(:reader_state_reader) { instance_double('ReaderStateReader') }
  let(:progress_presenter) { instance_double('ProgressPresenter') }
  let(:reader_launch_service) do
    instance_double(
      'ReaderLaunchService',
      open_selected_book: nil,
      open_book: nil,
      run_reader: nil,
      load_and_open_with_progress: nil,
      file_not_found: nil,
      handle_reader_error: nil,
      valid_cache_path?: true,
      ensure_reader_document_for: true
    )
  end
  let(:download_workflow) { instance_double('DownloadWorkflow', search_downloads: nil, download_book: nil) }
  let(:dictionary_workflow) { instance_double('DictionaryWorkflow', fetch_dictionary_catalog: nil, download_dictionary: nil) }
  let(:annotation_workflow) do
    instance_double(
      'AnnotationWorkflow',
      open_selected_annotation: nil,
      open_selected_annotation_for_edit: nil,
      delete_selected_annotation: nil,
      save_current_annotation_edit: nil
    )
  end

  def default_deps(overrides = {})
    {
      pagination_orchestrator: pagination_orchestrator,
      clock: clock,
      reader_session_context: reader_session_context,
      menu_session_context: menu_session_context,
      menu_state_reader: menu_state_reader,
      menu_state_writer: menu_state_writer,
      state_writer: state_writer,
      reader_state_reader: reader_state_reader,
      selected_book_reader: -> {},
      annotation_selection_reader: -> { [nil, nil] },
      annotation_view_refresher: -> {},
      build_reader_controller: ->(*, **) {},
      reader_launch_dependencies_factory: ->(**kwargs) { kwargs },
      reader_launch_service_factory: ->(_deps) { reader_launch_service },
      download_workflow_factory: ->(**) { download_workflow },
      dictionary_workflow_factory: ->(**) { dictionary_workflow },
      annotation_workflow_factory: ->(**) { annotation_workflow },
      progress_presenter_factory: -> { progress_presenter },
    }.merge(overrides)
  end

  def build_controller(overrides = {})
    described_class.new(menu, **default_deps(overrides))
  end

  it 'fails fast when required session contexts are missing' do
    expect do
      build_controller(reader_session_context: nil)
    end.to raise_error(ArgumentError, 'reader_session_context is required')

    expect do
      build_controller(menu_session_context: nil)
    end.to raise_error(ArgumentError, 'menu_session_context is required')
  end

  it 'requires all workflow factories to be callable' do
    expect do
      build_controller(reader_launch_dependencies_factory: nil)
    end.to raise_error(ArgumentError, 'reader_launch_dependencies_factory is required and must respond to :call')

    expect do
      build_controller(reader_launch_service_factory: nil)
    end.to raise_error(ArgumentError, 'reader_launch_service_factory is required and must respond to :call')

    expect do
      build_controller(download_workflow_factory: nil)
    end.to raise_error(ArgumentError, 'download_workflow_factory is required and must respond to :call')

    expect do
      build_controller(dictionary_workflow_factory: nil)
    end.to raise_error(ArgumentError, 'dictionary_workflow_factory is required and must respond to :call')

    expect do
      build_controller(annotation_workflow_factory: nil)
    end.to raise_error(ArgumentError, 'annotation_workflow_factory is required and must respond to :call')

    expect do
      build_controller(progress_presenter_factory: nil)
    end.to raise_error(ArgumentError, 'progress_presenter_factory is required and must respond to :call')
  end

  it 'delegates reader lifecycle methods to injected reader launch service' do
    controller = build_controller
    error = RuntimeError.new('boom')

    expect(reader_launch_service).to receive(:open_selected_book).once
    expect(reader_launch_service).to receive(:open_book).with('/tmp/book.epub').once
    expect(reader_launch_service).to receive(:run_reader).with('/tmp/book.epub').once
    expect(reader_launch_service).to receive(:load_and_open_with_progress).with('/tmp/book.epub').once
    expect(reader_launch_service).to receive(:file_not_found).once
    expect(reader_launch_service).to receive(:handle_reader_error).with('/tmp/book.epub', error).once
    expect(reader_launch_service).to receive(:valid_cache_path?).with('/tmp/book.cache').and_return(false).once

    controller.open_selected_book
    controller.open_book('/tmp/book.epub')
    controller.run_reader('/tmp/book.epub')
    controller.load_and_open_with_progress('/tmp/book.epub')
    controller.file_not_found
    controller.handle_reader_error('/tmp/book.epub', error)
    expect(controller.valid_cache_path?('/tmp/book.cache')).to be(false)
  end

  it 'delegates download, dictionary, and annotation actions to injected workflows' do
    controller = build_controller

    expect(download_workflow).to receive(:search_downloads).with(query: 'austen', page_url: nil).once
    expect(download_workflow).to receive(:download_book).with({ title: 'Persuasion' }).once
    expect(dictionary_workflow).to receive(:fetch_dictionary_catalog).once
    expect(dictionary_workflow).to receive(:download_dictionary).with({ name: 'en-en' }).once
    expect(annotation_workflow).to receive(:open_selected_annotation).once
    expect(annotation_workflow).to receive(:open_selected_annotation_for_edit).once
    expect(annotation_workflow).to receive(:delete_selected_annotation).once
    expect(annotation_workflow).to receive(:save_current_annotation_edit).once

    controller.search_downloads(query: 'austen')
    controller.download_book({ title: 'Persuasion' })
    controller.fetch_dictionary_catalog
    controller.download_dictionary({ name: 'en-en' })
    controller.open_selected_annotation
    controller.open_selected_annotation_for_edit
    controller.delete_selected_annotation
    controller.save_current_annotation_edit
  end

  it 'wires progress presenter to reader launch workflow through injected factory only' do
    captured_reader = nil
    captured_reader_deps = nil
    captured_download = nil
    captured_dictionary = nil

    dependencies_factory = lambda do |**kwargs|
      captured_reader_deps = kwargs
      kwargs
    end
    reader_launch_factory = lambda do |deps|
      captured_reader = deps
      reader_launch_service
    end
    download_factory = lambda do |**kwargs|
      captured_download = kwargs
      download_workflow
    end
    dictionary_factory = lambda do |**kwargs|
      captured_dictionary = kwargs
      dictionary_workflow
    end
    annotation_factory = ->(**) { annotation_workflow }

    build_controller(
      reader_launch_dependencies_factory: dependencies_factory,
      reader_launch_service_factory: reader_launch_factory,
      download_workflow_factory: download_factory,
      dictionary_workflow_factory: dictionary_factory,
      annotation_workflow_factory: annotation_factory
    )

    expect(captured_reader).to eq(captured_reader_deps)
    expect(captured_reader[:progress_presenters])
      .to be_a(Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchProgressPresenters)
    expect(captured_reader[:book_selection])
      .to be_a(Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchBookSelectionBridge)
    expect(captured_reader[:menu_runtime])
      .to be_a(Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchRuntimeBridge)

    expect(captured_download).to include(
      menu_runtime: kind_of(Shoko::Adapters::Input::Controllers::Menu::MenuWorkflowRuntimeBridge)
    )
    expect(captured_dictionary).to include(
      menu_runtime: kind_of(Shoko::Adapters::Input::Controllers::Menu::MenuWorkflowRuntimeBridge)
    )
    expect(captured_download[:menu_runtime]).to eq(captured_dictionary[:menu_runtime])

    expect(captured_reader[:progress_presenters].build).to eq(progress_presenter)
    expect(captured_reader[:book_selection].selected_book).to be_nil
  end
end
