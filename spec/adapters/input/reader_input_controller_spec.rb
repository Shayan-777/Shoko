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
        attr_reader :command_bus, :state_controller

        def initialize(command_bus, state_controller)
          @command_bus = command_bus
          @state_controller = state_controller
        end

        def quit_to_menu
          state_controller.quit_to_menu
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
        attr_reader :command_bus, :bookmark_service, :reader_state_reader

        def initialize(command_bus, bookmark_service, reader_state_reader)
          @command_bus = command_bus
          @bookmark_service = bookmark_service
          @reader_state_reader = reader_state_reader
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
end
