# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Application state and input port contracts' do
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
    implementation = build_implementation(Shoko::Application::Ports::UiStateReader)
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
    implementation = build_implementation(Shoko::Application::Ports::SidebarStateReader)
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

  it 'defines InputSystemFactory contract methods' do
    implementation = build_implementation(Shoko::Application::Ports::InputSystemFactory)
    methods = [
      [:create_reader_input_controller, [], { reader_state_reader: nil, state_writer: nil, command_port: nil }],
      [:create_menu_dispatcher, [Object.new], nil],
      [:create_mouse_handler, [], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines PaginationStateWriter contract methods' do
    implementation = build_implementation(Shoko::Application::Ports::PaginationStateWriter)
    methods = [
      [:update_pagination_state, [{}], nil],
      [:update_page, [{}], nil],
      [:update_selections, [{}], nil],
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderStateWriter contract methods' do
    implementation = build_implementation(Shoko::Application::Ports::ReaderStateWriter)
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
end
