# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Commands do
  let(:logger) { instance_double('Logger', error: nil) }

  let(:context_class) do
    Class.new do
      include Shoko::Core::Ports::Inbound::IntentDispatchContext

      attr_reader :command_bus

      def initialize(command_bus, logger)
        @command_bus = command_bus
        @logger = logger
      end

      def command_logger
        @logger
      end
    end
  end

  let(:fake_bus_class) do
    Class.new do
      include Shoko::Core::Ports::Inbound::CommandBus

      attr_reader :last_payload, :last_symbol, :last_context

      def build_command(_command_symbol, _params = {})
        nil
      end

      def execute_command(command_symbol, context, params = {})
        @last_symbol = command_symbol
        @last_context = context
        @last_payload = params
        :handled
      end

      def command_exists?(_command_symbol)
        true
      end
    end
  end

  it 'routes symbol execution through typed InputCommandPayload' do
    bus = fake_bus_class.new
    context = context_class.new(bus, logger)

    result = described_class.execute(:next_page, context, 'k')

    expect(result).to eq(:handled)
    expect(bus.last_symbol).to eq(:next_page)
    expect(bus.last_payload).to be_a(Shoko::Application::UseCases::Commands::InputCommandPayload)
    expect(bus.last_payload.key).to eq('k')
    expect(bus.last_payload.triggered_by).to eq(:input)
    expect(bus.last_payload.args).to eq([])
  end

  it 'routes array symbol commands through typed payload args' do
    bus = fake_bus_class.new
    context = context_class.new(bus, logger)

    result = described_class.execute([:next_page, 1, 2, 3], context, 'k')

    expect(result).to eq(:handled)
    expect(bus.last_symbol).to eq(:next_page)
    expect(bus.last_payload.args).to eq([1, 2, 3])
  end

  it 'returns :error and logs command.contract_mismatch when command bus is missing' do
    context = Class.new do
      include Shoko::Core::Ports::Inbound::IntentDispatchContext

      def initialize(logger)
        @logger = logger
      end

      def intent_handler
        nil
      end

      def command_bus
        nil
      end

      def command_logger
        @logger
      end
    end.new(logger)

    result = described_class.execute(:next_page, context, 'k')

    expect(result).to eq(:error)
    expect(logger).to have_received(:error).with(
      'command.contract_mismatch',
      hash_including(command: :next_page, reason: 'missing_command_bus')
    )
  end

  it 'returns :error and logs command.contract_mismatch for malformed array command payloads' do
    bus = fake_bus_class.new
    context = context_class.new(bus, logger)

    result = described_class.execute([123, :bad], context, 'k')

    expect(result).to eq(:error)
    expect(logger).to have_received(:error).with(
      'command.contract_mismatch',
      hash_including(command: '[123, :bad]')
    )
  end
end
