# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Input command binding completeness' do
  let(:command_port) { Shoko::Adapters::State::CommandPortAdapter.new }

  def extract_command_symbols(dispatcher)
    command_map = dispatcher.instance_variable_get(:@command_map) || {}
    command_map.values.flat_map(&:values).select { |value| value.is_a?(Symbol) }.uniq
  end

  it 'ensures reader input bindings map only to registered command port symbols' do
    state = instance_double('State')
    reader_state_reader = instance_double('ReaderStateReader', popup_menu: nil, mode: :read)
    state_writer = instance_double('StateWriter')
    ui_controller = instance_double('UIController')

    controller = Shoko::Adapters::Input::InputController.new(
      state,
      reader_state_reader: reader_state_reader,
      state_writer: state_writer,
      command_port: command_port,
      ui_controller: ui_controller
    )

    reader_context = Struct.new(:command_port).new(command_port)
    controller.setup_input_dispatcher(reader_context)
    symbols = extract_command_symbols(controller.instance_variable_get(:@dispatcher))

    missing = symbols.reject { |symbol| command_port.command_exists?(symbol) }
    expect(missing).to be_empty, "Reader bindings reference unknown commands: #{missing.join(', ')}"
  end

  it 'ensures menu input bindings map only to registered command port symbols' do
    menu_context = Struct.new(:command_port).new(command_port)
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

    input = Shoko::Application::Controllers::Menu::InputController.new(
      menu,
      key_classifier: key_classifier,
      input_system_factory: dispatcher_factory
    )

    symbols = extract_command_symbols(input.dispatcher)
    missing = symbols.reject { |symbol| command_port.command_exists?(symbol) }
    expect(missing).to be_empty, "Menu bindings reference unknown commands: #{missing.join(', ')}"
  end
end
