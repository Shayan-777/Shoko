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

  it 'defines UiStateReader contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::UiStateReader)
    methods = [
      [:terminal_width, [], nil],
      [:terminal_height, [], nil],
      [:loading_message, [], nil],
      [:loading_progress, [], nil],
      [:terminal_size_changed?, [80, 24], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines SidebarStateReader contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::SidebarStateReader)
    methods = %i[
      sidebar_visible?
      sidebar_active_tab
      sidebar_toc_selected
      sidebar_toc_collapsed
      sidebar_bookmarks_selected
      sidebar_annotations_selected
      sidebar_prev_view_mode
      sidebar_toc_filter
      sidebar_toc_filter_active?
    ].map { |name| [name, [], nil] }

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines CommandBus inbound contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Inbound::CommandBus)
    methods = [
      [:build_command, [:next_page], nil],
      [:execute_command, [:next_page, Object.new], nil],
      [:command_exists?, [:next_page], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines PaginationStateWriter contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::PaginationStateWriter)
    methods = [
      [:update_pagination_state, [{}], nil],
      [:update_page, [{}], nil],
      [:update_selections, [{}], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderStateWriter contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderStateWriter)
    methods = [
      [:update_reader, [{}], nil],
      [:update_navigation, [{}], nil],
      [:update_bookmarks, [[]], nil],
      [:update_sidebar, [{}], nil],
      [:update_config, [{}], nil],
      [:clear_selection, [], nil],
      [:quit_to_menu, [], nil],
      [:update_reader_meta, [{}], nil],
      [:update_terminal_size, [80, 24], nil],
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
