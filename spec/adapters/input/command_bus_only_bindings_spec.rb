# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Command-bus-only input bindings' do
  let(:command_bus) { Shoko::Application::UseCases::CommandBus.new }

  def extract_commands(dispatcher)
    command_map = dispatcher.instance_variable_get(:@command_map) || {}
    command_map.values.flat_map(&:values).uniq
  end

  def binding_type_summary(bindings)
    bindings
      .group_by { |binding| binding.class.name }
      .map { |klass, values| "#{klass}=#{values.size}" }
      .sort
      .join(', ')
  end

  def expect_symbol_only_bindings!(bindings, layer:)
    non_symbols = bindings.reject { |binding| binding.is_a?(Symbol) }
    expect(non_symbols).to be_empty,
                              "#{layer} bindings must be command symbols only. Found: #{binding_type_summary(bindings)}"

    unknown = bindings.reject { |symbol| command_bus.command_exists?(symbol) }
    expect(unknown).to be_empty,
                            "#{layer} bindings reference unknown command symbols: #{unknown.uniq.sort.join(', ')}"

    expect(bindings).not_to be_empty, "#{layer} bindings must expose at least one registered command symbol"
  end

  it 'forces reader bindings to use command bus symbols only' do
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

    bindings = extract_commands(controller.instance_variable_get(:@dispatcher))
    expect_symbol_only_bindings!(bindings, layer: 'Reader input')
  end

  it 'forces menu bindings to use command bus symbols only' do
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

    bindings = extract_commands(input.dispatcher)
    expect_symbol_only_bindings!(bindings, layer: 'Menu input')
  end
end
