# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Input command binding completeness' do
  let(:command_bus) { Shoko::Application::UseCases::CommandBus.new }

  def extract_commands(dispatcher)
    command_map = dispatcher.instance_variable_get(:@command_map) || {}
    command_map.values.flat_map(&:values).uniq
  end

  it 'ensures reader input symbol bindings map only to semantic bus commands' do
    reader_state_reader = instance_double('ReaderStateReader', popup_menu: nil, mode: :read)
    state_writer = instance_double('StateWriter')
    ui_controller = instance_double('UIController')

    controller = Shoko::Adapters::Input::ReaderInputController.new(
      reader_state_reader: reader_state_reader,
      state_writer: state_writer,
      command_bus: command_bus,
      ui_controller: ui_controller
    )

    reader_context = Struct.new(:command_bus).new(command_bus)
    controller.setup_input_dispatcher(reader_context)
    commands = extract_commands(controller.instance_variable_get(:@dispatcher))
    symbols = commands.select { |value| value.is_a?(Symbol) }

    missing = symbols.reject { |symbol| command_bus.command_exists?(symbol) }
    expect(missing).to be_empty, "Reader bindings reference unknown commands: #{missing.join(', ')}"
    expect(commands.any? { |value| value.is_a?(Proc) }).to eq(true), 'Reader bindings should include adapter-local lambdas'
  end

  it 'allows menu input adapter-local lambda bindings without command bus symbols' do
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

    commands = extract_commands(input.dispatcher)
    symbols = commands.select { |value| value.is_a?(Symbol) }
    expect(symbols).to be_empty, "Menu bindings should not rely on command bus symbols: #{symbols.join(', ')}"
    expect(commands.any? { |value| value.is_a?(Proc) }).to eq(true), 'Menu bindings should include adapter-local lambdas'
  end
end
