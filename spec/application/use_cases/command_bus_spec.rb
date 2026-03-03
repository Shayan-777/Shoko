# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::CommandBus do
  subject(:command_bus) { described_class.new }

  it 'builds semantic commands from explicit registry entries' do
    command = command_bus.build_command(:next_page)

    expect(command).to be_a(Shoko::Application::UseCases::Commands::NavigationCommand)
  end

  it 'builds explicit reader intent commands for adapter actions' do
    handler_class = Class.new do
      include Shoko::Core::Ports::Inbound::ReaderIntentHandler

      attr_reader :called

      def handle_reader_intent(intent_symbol, _payload = nil)
        return :pass unless intent_symbol == :quit_to_menu

        @called = true
        :handled
      end

      def command_logger
        nil
      end
    end

    context = Class.new do
      include Shoko::Core::Ports::Inbound::IntentDispatchContext

      def initialize(handler)
        @handler = handler
      end

      def intent_handler
        @handler
      end

      def command_logger
        nil
      end
    end.new(handler_class.new)

    command = command_bus.build_command(:quit_to_menu)

    expect(command).to be_a(Shoko::Application::UseCases::Commands::ReaderIntentCommand)
    expect(command.execute(context)).to eq(:handled)
    expect(context.intent_handler.called).to eq(true)
  end

  it 'executes reader intents with typed payload' do
    handler_class = Class.new do
      include Shoko::Core::Ports::Inbound::ReaderIntentHandler

      attr_reader :called

      def handle_reader_intent(intent_symbol, payload = nil)
        return :pass unless intent_symbol == :quit_to_menu

        @received_payload = payload
        @called = true
        :handled
      end

      def command_logger
        nil
      end

      def received_payload
        @received_payload
      end
    end

    context = Class.new do
      include Shoko::Core::Ports::Inbound::IntentDispatchContext

      def initialize(handler)
        @handler = handler
      end

      def intent_handler
        @handler
      end

      def command_logger
        nil
      end
    end.new(handler_class.new)

    expect(command_bus.execute_command(:quit_to_menu, context, key: 'q')).to eq(:handled)
    expect(context.intent_handler.called).to eq(true)
    expect(context.intent_handler.received_payload).to be_a(Shoko::Core::Ports::Inbound::InputCommandPayload)
    expect(context.intent_handler.received_payload.key).to eq('q')
  end

  it 'rejects unknown symbols outside the command whitelist' do
    expect(command_bus.command_exists?(:unknown_command)).to eq(false)
    expect(command_bus.build_command(:unknown_command)).to be_nil
    expect(command_bus.execute_command(:unknown_command, Object.new)).to eq(:error)
  end

  it 'returns :error when semantic command context fails typed contract validation' do
    expect(command_bus.execute_command(:next_page, Object.new, key: 'j')).to eq(:error)
  end
end
