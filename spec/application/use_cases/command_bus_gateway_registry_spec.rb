# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Command bus intent registry' do
  let(:command_bus) { Shoko::Application::UseCases::CommandBus.new }

  def extract_symbols(dispatcher)
    command_map = dispatcher.instance_variable_get(:@command_map) || {}
    command_map.values.flat_map(&:values).select { |value| value.is_a?(Symbol) }.uniq.sort
  end

  def reader_binding_symbols
    reader_state_reader = instance_double('ReaderStateReader', popup_menu: nil, mode: :read)
    state_writer = instance_double('StateWriter')
    ui_controller = instance_double('UIController')

    controller = Shoko::Adapters::Input::ReaderInputController.new(
      reader_state_reader: reader_state_reader,
      state_writer: state_writer,
      command_bus: command_bus,
      ui_controller: ui_controller
    )

    context = Struct.new(:command_bus).new(command_bus)
    controller.setup_input_dispatcher(context)
    extract_symbols(controller.instance_variable_get(:@dispatcher))
  end

  def menu_binding_symbols
    menu_context = Struct.new(:command_bus).new(command_bus)
    dispatcher_factory = Class.new do
      def initialize(dispatcher)
        @dispatcher = dispatcher
      end

      def create_menu_dispatcher(_menu)
        @dispatcher
      end
    end.new(Shoko::Adapters::Input::Dispatcher.new(menu_context))

    key_classifier = Shoko::Adapters::Input::KeyClassifierAdapter.new(
      command_factory: Shoko::Adapters::Input::CommandFactory
    )
    menu_reader = instance_double('MenuStateReader', mode: :menu)
    menu = instance_double('MenuController', menu_state_reader: menu_reader)

    input = Shoko::Adapters::Input::Controllers::Menu::InputController.new(
      menu,
      key_classifier: key_classifier,
      input_system_factory: dispatcher_factory
    )

    extract_symbols(input.dispatcher)
  end

  it 'covers every reader/menu bound symbol in command bus registry' do
    all_symbols = (reader_binding_symbols + menu_binding_symbols).uniq
    missing = all_symbols.reject { |symbol| command_bus.command_exists?(symbol) }

    expect(missing).to eq([])
  end

  it 'keeps reader and menu symbol snapshots stable' do
    expect(reader_binding_symbols).to eq(%i[
                                         add_bookmark
                                         annotation_editor_backspace
                                         annotation_editor_cancel
                                         annotation_editor_enter
                                         annotation_editor_insert_char_if_printable
                                         annotation_editor_move_down
                                         annotation_editor_move_left
                                         annotation_editor_move_right
                                         annotation_editor_move_up
                                         annotation_editor_save
                                         annotation_editor_spellcheck
                                         decrease_line_spacing
                                         dictionary_backspace
                                         dictionary_cancel
                                         dictionary_confirm
                                         dictionary_cycle_pair
                                         dictionary_cycle_result
                                         dictionary_insert_char_if_printable
                                         dictionary_scroll_down
                                         dictionary_scroll_up
                                         dictionary_swap_languages
                                         dictionary_toggle_fuzzy
                                         go_to_end
                                         go_to_start
                                         handle_popup_action_key
                                         handle_popup_cancel
                                         handle_popup_navigation
                                         help_exit_to_read
                                         in_book_search_backspace
                                         in_book_search_cancel
                                         in_book_search_confirm
                                         in_book_search_down
                                         in_book_search_insert_char_if_printable
                                         in_book_search_up
                                         increase_line_spacing
                                         invalidate_pagination_cache
                                         next_chapter
                                         next_page
                                         open_annotations
                                         open_annotations_tab
                                         open_bookmarks
                                         open_in_book_search
                                         open_toc
                                         prev_chapter
                                         prev_page
                                         quit_application
                                         quit_to_menu
                                         read_confirm_or_sidebar
                                         read_scroll_down_or_sidebar
                                         read_scroll_up_or_sidebar
                                         read_space_or_sidebar_toggle
                                         rebuild_pagination
                                         show_help
                                         toggle_page_numbering_mode
                                         toggle_view_mode
                                       ])

    expect(menu_binding_symbols).to eq(%i[
                                       annotation_editor_backspace
                                       annotation_editor_cancel
                                       annotation_editor_enter
                                       annotation_editor_insert_char
                                       annotation_editor_move_down
                                       annotation_editor_move_left
                                       annotation_editor_move_right
                                       annotation_editor_move_up
                                       annotation_editor_save
                                       annotations_down
                                       annotations_select
                                       annotations_up
                                       browse_down
                                       browse_up
                                       delete_selected_annotation
                                       dictionary_back
                                       dictionary_down
                                       dictionary_exit_search
                                       dictionary_refresh
                                       dictionary_search_backspace
                                       dictionary_search_delete
                                       dictionary_search_insert_char
                                       dictionary_select
                                       dictionary_start_search
                                       dictionary_submit_search
                                       dictionary_up
                                       download_confirm
                                       download_down
                                       download_exit_search
                                       download_next_page
                                       download_prev_page
                                       download_refresh
                                       download_search_backspace
                                       download_search_delete
                                       download_search_insert_char
                                       download_start_search
                                       download_submit_search
                                       download_up
                                       library_down
                                       library_select
                                       library_toggle_details
                                       library_up
                                       menu_back_to_root
                                       menu_nav_down
                                       menu_nav_up
                                       menu_quit
                                       menu_select
                                       open_selected_annotation
                                       open_selected_annotation_for_edit
                                       open_selected_book
                                       search_backspace
                                       search_delete
                                       search_insert_char
                                       settings_down
                                       settings_select
                                       settings_up
                                       switch_to_annotations_mode
                                       switch_to_browse
                                       switch_to_search
                                     ])
  end

  it 'builds explicit command objects for reader/menu intent symbols' do
    semantic = Shoko::Application::UseCases::CommandBus::SEMANTIC_COMMAND_REGISTRY.keys
    shared = Shoko::Application::UseCases::CommandBus::SHARED_INTENT_SYMBOLS
    reader = Shoko::Application::UseCases::CommandBus::READER_INTENT_COMMAND_REGISTRY.keys
    menu = Shoko::Application::UseCases::CommandBus::MENU_INTENT_COMMAND_REGISTRY.keys

    (reader_binding_symbols + menu_binding_symbols).uniq.each do |symbol|
      command = command_bus.build_command(symbol)
      expect(command).not_to be_nil

      if semantic.include?(symbol)
        expect(command).to be_a(Shoko::Application::UseCases::Commands::BaseCommand)
      elsif shared.include?(symbol)
        expect(command).to be_a(Shoko::Application::UseCases::Commands::Shared::AnnotationEditorCommand)
      elsif reader.include?(symbol)
        expect(command.class.name).to start_with('Shoko::Application::UseCases::Commands::Reader::')
      elsif menu.include?(symbol)
        expect(command.class.name).to start_with('Shoko::Application::UseCases::Commands::Menu::')
      else
        raise "Symbol #{symbol} was not present in any registry"
      end
    end
  end

  it 'routes shared symbols through explicit shared intent symbols' do
    reader = Shoko::Application::UseCases::CommandBus::READER_INTENT_COMMAND_REGISTRY.keys
    menu = Shoko::Application::UseCases::CommandBus::MENU_INTENT_COMMAND_REGISTRY.keys
    shared = Shoko::Application::UseCases::CommandBus::SHARED_INTENT_SYMBOLS

    expected_shared = (
      Shoko::Core::Ports::Inbound::ReaderIntentHandler::INTENT_SYMBOLS &
      Shoko::Core::Ports::Inbound::MenuIntentHandler::INTENT_SYMBOLS
    ).sort

    expect(shared.sort).to eq(expected_shared)
    expect((reader & menu).sort).to eq([])
    expect(shared).not_to be_empty
  end

  it 'returns :error and logs command.unknown for unknown symbols' do
    logger = instance_double('Logger', error: nil)
    context = Class.new do
      include Shoko::Core::Ports::Inbound::IntentDispatchContext

      def initialize(logger)
        @logger = logger
      end

      def intent_handler
        nil
      end

      def command_logger
        @logger
      end
    end.new(logger)

    result = command_bus.execute_command(:totally_unknown_symbol, context)

    expect(result).to eq(:error)
    expect(logger).to have_received(:error).with(
      'command.unknown',
      hash_including(command: :totally_unknown_symbol)
    )
  end

  it 'returns :error and logs command.invalid_payload for payload conversion errors' do
    logger = instance_double('Logger', error: nil)
    context_class = Class.new do
      include Shoko::Core::Ports::Inbound::IntentDispatchContext

      def initialize(logger)
        @logger = logger
      end

      def command_bus
        nil
      end

      def command_logger
        @logger
      end
    end
    context = context_class.new(logger)

    result = command_bus.execute_command(:quit_to_menu, context, Object.new)

    expect(result).to eq(:error)
    expect(logger).to have_received(:error).with(
      'command.invalid_payload',
      hash_including(command: :quit_to_menu)
    )
  end

  it 'returns :error and logs command.contract_mismatch when context violates intent contract' do
    logger = instance_double('Logger', error: nil)
    context = Class.new do
      include Shoko::Core::Ports::Inbound::IntentDispatchContext

      def initialize(logger)
        @logger = logger
      end

      def command_bus
        nil
      end

      def command_logger
        @logger
      end
    end.new(logger)

    result = command_bus.execute_command(:quit_to_menu, context)

    expect(result).to eq(:error)
    expect(logger).to have_received(:error).with(
      'command.contract_mismatch',
      hash_including(command: :quit_to_menu)
    )
  end
end
