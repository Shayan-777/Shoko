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

  it 'defines ReaderIntentRuntime contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderIntentRuntime)
    methods = [
      [:open_toc_sidebar, [], nil],
      [:sidebar_move, [-1], nil],
      [:dictionary_insert_text, ['x'], nil],
      [:annotation_editor_move, [:left], nil],
      [:quit_to_menu, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuIntentRuntime contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuIntentRuntime)
    methods = [
      [:activate_mode, [:browse], nil],
      [:browse_items_count, [], nil],
      [:selected_library_target_path, [], nil],
      [:annotation_editor_insert_text, ['x'], nil],
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
      [:save, [Shoko::Core::Models::Session::MenuSnapshot.build], nil],
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
