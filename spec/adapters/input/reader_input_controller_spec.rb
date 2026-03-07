# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::ReaderInputController do
  describe "read-mode quit binding" do
    let(:reader_state_reader) { instance_double('ReaderStateReader') }
    let(:state_writer) { instance_double('StateWriter') }
    let(:command_bus) { Shoko::Application::UseCases::CommandBus.new }
    let(:state_controller) { instance_double('StateController', quit_to_menu: nil) }
    let(:intent_handler_class) do
      Class.new do
        include Shoko::Core::Ports::Inbound::ReaderIntentHandler

        attr_reader :state_controller

        def initialize(state_controller)
          @state_controller = state_controller
        end

        def handle_reader_intent(intent_symbol, _payload = nil)
          return :pass unless intent_symbol == :quit_to_menu

          state_controller.quit_to_menu
          :handled
        end

        def command_logger
          nil
        end
      end
    end
    let(:context_class) do
      Class.new do
        include Shoko::Core::Ports::Inbound::IntentDispatchContext

        attr_reader :command_bus, :state_controller

        def initialize(command_bus, state_controller, intent_handler)
          @command_bus = command_bus
          @state_controller = state_controller
          @intent_handler = intent_handler
        end

        def intent_handler
          @intent_handler
        end

        def command_logger
          nil
        end
      end
    end
    let(:context) { context_class.new(command_bus, state_controller, intent_handler_class.new(state_controller)) }

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

        def intent_handler
          nil
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
        include Shoko::Core::Ports::Inbound::ReaderIntentHandler

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

        def intent_handler
          self
        end

        def handle_reader_intent(intent_symbol, payload = nil)
          key = payload&.key

          case intent_symbol
          when :open_toc then open_toc(key)
          when :annotation_editor_insert_char_if_printable then annotation_editor_insert_char_if_printable(key)
          when :annotation_editor_spellcheck then annotation_editor_spellcheck
          when :dictionary_insert_char_if_printable then dictionary_insert_char_if_printable(key)
          when :in_book_search_insert_char_if_printable then in_book_search_insert_char_if_printable(key)
          else
            :pass
          end
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

        def dictionary_insert_char_if_printable(key = nil)
          @dictionary_chars << key
          :handled
        end

        def in_book_search_insert_char_if_printable(key = nil)
          @search_chars << key
          :handled
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
