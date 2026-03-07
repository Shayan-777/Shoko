# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::ReaderInputController do
  describe "read-mode quit binding" do
    let(:reader_state_reader) { instance_double('ReaderStateReader') }
    let(:state_writer) { instance_double('StateWriter') }
    let(:command_bus) { Shoko::Application::UseCases::CommandBus.new }
    let(:state_controller) { instance_double('StateController', quit_to_menu: nil) }
    let(:context_class) do
      Class.new do
        include Shoko::Core::Ports::Inbound::IntentDispatchContext
        include Shoko::Core::Ports::Inbound::ReaderLifecycleCommandContext

        attr_reader :command_bus, :state_controller

        def initialize(command_bus, state_controller)
          @command_bus = command_bus
          @state_controller = state_controller
        end

        def rebuild_pagination
          raise 'not used'
        end

        def invalidate_pagination_cache
          raise 'not used'
        end

        def quit_to_menu
          state_controller.quit_to_menu
        end

        def quit_application
          raise 'not used'
        end

        def command_logger
          nil
        end
      end
    end
    let(:context) { context_class.new(command_bus, state_controller) }

    it "dispatches 'q' to quit_to_menu" do
      controller = described_class.new(
        reader_state_reader: reader_state_reader,
        state_writer: state_writer,
        command_bus: command_bus
      )
      controller.setup_input_dispatcher(context)

      controller.handle_key('q')

      expect(state_controller).to have_received(:quit_to_menu)
    end
  end

  describe 'read-mode bookmark binding' do
    let(:reader_state_reader) { instance_double('ReaderStateReader', popup_menu: nil, mode: :read) }
    let(:state_writer) { instance_double('StateWriter') }
    let(:command_bus) { Shoko::Application::UseCases::CommandBus.new }
    let(:bookmark_service) { instance_double('BookmarkService', add_bookmark: nil) }
    let(:context_class) do
      Class.new do
        include Shoko::Core::Ports::Inbound::IntentDispatchContext
        include Shoko::Core::Ports::Inbound::ReaderBookmarkCommandContext

        attr_reader :command_bus, :bookmark_service, :reader_state_reader

        def initialize(command_bus, bookmark_service, reader_state_reader)
          @command_bus = command_bus
          @bookmark_service = bookmark_service
          @reader_state_reader = reader_state_reader
        end

        def command_logger
          nil
        end
      end
    end

    it "dispatches 'b' to add_bookmark" do
      context = context_class.new(command_bus, bookmark_service, reader_state_reader)
      controller = described_class.new(
        reader_state_reader: reader_state_reader,
        state_writer: state_writer,
        command_bus: command_bus
      )
      controller.setup_input_dispatcher(context)

      controller.handle_key('b')

      expect(bookmark_service).to have_received(:add_bookmark).with(nil)
    end
  end

  describe 'modal isolation' do
    let(:reader_state_reader) { instance_double('ReaderStateReader', popup_menu: nil, mode: :read) }
    let(:state_writer) { instance_double('StateWriter') }
    let(:command_bus) { Shoko::Application::UseCases::CommandBus.new }

    let(:context_class) do
      Class.new do
        include Shoko::Core::Ports::Inbound::IntentDispatchContext
        include Shoko::Core::Ports::Inbound::ReaderOverlayCommandContext
        include Shoko::Core::Ports::Inbound::ReaderDictionaryCommandContext
        include Shoko::Core::Ports::Inbound::ReaderSearchCommandContext
        include Shoko::Core::Ports::Inbound::ReaderAnnotationEditorCommandContext

        attr_reader :command_bus, :open_toc_calls, :annotation_chars, :dictionary_chars, :search_chars,
                    :annotation_spellcheck_calls

        def initialize(command_bus)
          @command_bus = command_bus
          @open_toc_calls = 0
          @annotation_chars = []
          @dictionary_chars = []
          @search_chars = []
          @annotation_spellcheck_calls = 0
        end

        def command_logger
          nil
        end

        def open_bookmarks
          raise 'not used'
        end

        def open_annotations_tab
          raise 'not used'
        end

        def open_annotations
          raise 'not used'
        end

        def show_help(_key = nil)
          raise 'not used'
        end

        def toggle_view_mode(_key = nil)
          raise 'not used'
        end

        def increase_line_spacing(_key = nil)
          raise 'not used'
        end

        def decrease_line_spacing(_key = nil)
          raise 'not used'
        end

        def toggle_page_numbering_mode(_key = nil)
          raise 'not used'
        end

        def handle_popup_action_key(key = nil)
          raise "unexpected popup action #{key.inspect}"
        end

        def handle_popup_cancel(key = nil)
          raise "unexpected popup cancel #{key.inspect}"
        end

        def handle_popup_navigation(key = nil)
          raise "unexpected popup navigation #{key.inspect}"
        end

        def help_exit_to_read(_key = nil)
          raise 'not used'
        end

        def read_confirm_or_sidebar(key = nil)
          raise "unexpected confirm #{key.inspect}"
        end

        def read_scroll_down_or_sidebar(key = nil)
          raise "unexpected down #{key.inspect}"
        end

        def read_scroll_up_or_sidebar(key = nil)
          raise "unexpected up #{key.inspect}"
        end

        def read_space_or_sidebar_toggle(key = nil)
          raise "unexpected space #{key.inspect}"
        end

        def open_toc(_key = nil)
          @open_toc_calls += 1
          :handled
        end

        def annotation_editor_insert_char_if_printable(key = nil)
          @annotation_chars << key
          :handled
        end

        def annotation_editor_spellcheck
          @annotation_spellcheck_calls += 1
          :handled
        end

        def annotation_editor_backspace
          raise 'not used'
        end

        def annotation_editor_cancel
          raise 'not used'
        end

        def annotation_editor_enter
          raise 'not used'
        end

        def annotation_editor_move_down
          raise 'not used'
        end

        def annotation_editor_move_left
          raise 'not used'
        end

        def annotation_editor_move_right
          raise 'not used'
        end

        def annotation_editor_move_up
          raise 'not used'
        end

        def annotation_editor_save
          raise 'not used'
        end

        def dictionary_insert_char_if_printable(key = nil)
          @dictionary_chars << key
          :handled
        end

        def dictionary_backspace(_key = nil)
          raise 'not used'
        end

        def dictionary_cancel(_key = nil)
          raise 'not used'
        end

        def dictionary_confirm(_key = nil)
          raise 'not used'
        end

        def dictionary_cycle_pair(_key = nil)
          raise 'not used'
        end

        def dictionary_cycle_result(_key = nil)
          raise 'not used'
        end

        def dictionary_scroll_down(_key = nil)
          raise 'not used'
        end

        def dictionary_scroll_up(_key = nil)
          raise 'not used'
        end

        def dictionary_swap_languages(_key = nil)
          raise 'not used'
        end

        def dictionary_toggle_fuzzy(_key = nil)
          raise 'not used'
        end

        def in_book_search_insert_char_if_printable(key = nil)
          @search_chars << key
          :handled
        end

        def open_in_book_search(_key = nil)
          raise 'not used'
        end

        def in_book_search_backspace(_key = nil)
          raise 'not used'
        end

        def in_book_search_cancel(_key = nil)
          raise 'not used'
        end

        def in_book_search_confirm(_key = nil)
          raise 'not used'
        end

        def in_book_search_down(_key = nil)
          raise 'not used'
        end

        def in_book_search_up(_key = nil)
          raise 'not used'
        end
      end
    end

    it 'does not fall through to read bindings while in annotation editor mode' do
      context = context_class.new(command_bus)
      controller = described_class.new(
        reader_state_reader: reader_state_reader,
        state_writer: state_writer,
        command_bus: command_bus
      )
      controller.setup_input_dispatcher(context)
      controller.enter_modal_mode(:annotation_editor)

      controller.handle_key('t')

      expect(context.annotation_chars).to eq(['t'])
      expect(context.open_toc_calls).to eq(0)
    end

    it 'routes Alt+D to annotation spellcheck while in annotation editor mode' do
      context = context_class.new(command_bus)
      controller = described_class.new(
        reader_state_reader: reader_state_reader,
        state_writer: state_writer,
        command_bus: command_bus
      )
      controller.setup_input_dispatcher(context)
      controller.enter_modal_mode(:annotation_editor)

      controller.handle_key("\ed")

      expect(context.annotation_spellcheck_calls).to eq(1)
      expect(context.open_toc_calls).to eq(0)
    end

    it 'does not fall through to read bindings while in dictionary mode' do
      context = context_class.new(command_bus)
      controller = described_class.new(
        reader_state_reader: reader_state_reader,
        state_writer: state_writer,
        command_bus: command_bus
      )
      controller.setup_input_dispatcher(context)
      controller.enter_modal_mode(:dictionary)

      controller.handle_key('t')

      expect(context.dictionary_chars).to eq(['t'])
      expect(context.open_toc_calls).to eq(0)
    end

    it 'does not fall through to read bindings while in in-book search mode' do
      context = context_class.new(command_bus)
      controller = described_class.new(
        reader_state_reader: reader_state_reader,
        state_writer: state_writer,
        command_bus: command_bus
      )
      controller.setup_input_dispatcher(context)
      controller.enter_modal_mode(:in_book_search)

      controller.handle_key('t')

      expect(context.search_chars).to eq(['t'])
      expect(context.open_toc_calls).to eq(0)
    end
  end
end
