# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Application state and boundary port contracts' do
  def build_implementation(port_module)
    Class.new do
      include port_module
    end.new
  end

  def expect_contract_methods_to_raise(implementation, methods)
    methods.each do |method_name, args, kwargs|
      expect do
        if kwargs
          implementation.public_send(method_name, *args, **kwargs)
        else
          implementation.public_send(method_name, *args)
        end
      end.to raise_error(NotImplementedError)
    end
  end

  it 'defines ReaderDisplayControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderDisplayControl)
    methods = [
      [:show_toc_sidebar, [], nil],
      [:adjust_line_spacing, [], { delta: 1 }],
      [:move_sidebar_selection, [], { delta: -1 }],
      [:activate_sidebar_selection, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderPopupControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderPopupControl)
    methods = [
      [:move_popup_selection, [], { delta: -1 }],
      [:confirm_popup, [], nil],
      [:cancel_popup, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderDictionaryControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderDictionaryControl)
    methods = [
      [:open_dictionary_lookup, [], nil],
      [:append_dictionary_text, ['x'], nil],
      [:move_dictionary_selection, [], { delta: 1 }],
      [:toggle_dictionary_fuzzy_matching, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderSearchControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderSearchControl)
    methods = [
      [:open_search_session, [], nil],
      [:append_search_text, ['x'], nil],
      [:move_search_selection, [], { delta: -1 }],
      [:submit_search_session, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderAnnotationEditorControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderAnnotationEditorControl)
    methods = [
      [:append_annotation_text, ['x'], nil],
      [:move_annotation_cursor, [], { direction: :left }],
      [:save_annotation, [], nil],
      [:spellcheck_annotation, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderLifecycleControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderLifecycleControl)
    methods = [
      [:rebuild_pagination, [], nil],
      [:clear_pagination_cache, [], nil],
      [:return_to_menu, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuModeControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuModeControl)
    methods = [
      [:activate_menu_mode, [:browse], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuBrowseInspection contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuBrowseInspection)
    methods = [
      [:browse_item_count, [], nil],
      [:library_item_count, [], nil],
      [:selected_library_path, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuDownloadSelection contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuDownloadSelection)
    methods = [
      [:selected_download_result, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines CatalogRefreshControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::CatalogRefreshControl)
    methods = [
      [:refresh_catalog, [], { force: true }],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines DisplayMetadataCache contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::DisplayMetadataCache)
    methods = [
      [:fetch, [], { path: '/books/a.epub', size: 10, modified: '2024-01-01T00:00:00Z' }],
      [
        :write_success,
        [],
        { path: '/books/a.epub', size: 10, modified: '2024-01-01T00:00:00Z', metadata: { title: 'A' } },
      ],
      [
        :write_error,
        [],
        {
          path: '/books/a.epub',
          size: 10,
          modified: '2024-01-01T00:00:00Z',
          error_class: 'Error',
          error_message: 'bad',
        },
      ],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuAnnotationControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuAnnotationControl)
    methods = [
      [:move_annotation_selection, [], { delta: 1 }],
      [:selected_annotation_context, [], nil],
      [:append_annotation_text, ['x'], nil],
      [:move_annotation_cursor, [], { direction: :right }],
      [:save_annotation, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ApplicationExitControl contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ApplicationExitControl)
    methods = [
      [:quit_application, [], { code: 0, message: '' }],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderDocumentLocator contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderDocumentLocator)
    methods = [
      [:canonical_reader_path, ['/tmp/book.cache'], nil],
      [:resolve_source_path, ['/tmp/book.cache'], nil],
      [:document_matches_path?, [double('document'), '/books/a.epub'], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderSessionStore contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderSessionStore)
    methods = [
      [:load, [], nil],
      [:save, [Shoko::Core::Models::Session::ReaderSnapshot.build], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuSessionStore contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuSessionStore)
    methods = [
      [:load, [], nil],
      [:save, [Shoko::Core::Models::Session::MenuSessionSnapshot.build], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuTransientStore contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuTransientStore)
    methods = [
      [:load, [], nil],
      [:save, [Shoko::Core::Models::Session::MenuTransientSnapshot.build], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines AppConfigStore contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::AppConfigStore)
    methods = [
      [:load, [], nil],
      [:save, [Shoko::Core::Models::Session::ConfigSnapshot.build], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderRuntimeContext contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderRuntimeContext)
    methods = [
      [:terminal_size, [], nil],
      [:display_capabilities, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuReaderRuntime contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuReaderRuntime)
    methods = [
      [:run_reader, [], { path: '/books/a.epub', preloaded_document: nil, background_worker: nil }],
      [:switch_mode, [:browse], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderRenderRequester contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderRenderRequester)
    methods = [
      [:request_render, [], { reason: 'pagination.rebuild_dynamic' }]
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines FolderScanner and FolderImporter contract methods' do
    scanner = build_implementation(Shoko::Core::Ports::Outbound::FolderScanner)
    importer = build_implementation(Shoko::Core::Ports::Outbound::FolderImporter)

    expect do
      scanner.scan('/tmp/books', recursive: true, skip_hidden: true)
    end.to raise_error(NotImplementedError)

    expect do
      importer.import('/tmp/books/a.epub')
    end.to raise_error(NotImplementedError)
  end
end
