# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Intents::MenuIntentHandler do
  let(:logger) { instance_double('CommandLogger') }
  let(:executor_class) do
    Class.new do
      include Shoko::Core::Ports::Outbound::MenuIntentExecutor

      attr_reader :calls

      def initialize
        @calls = []
      end

      def execute(intent_symbol:, payload: nil)
        @calls << [intent_symbol, payload]
      end
    end
  end
  let(:executor) { executor_class.new }

  subject(:handler) do
    described_class.new(
      deps: described_class::Dependencies.new(intent_executor: executor, command_logger: logger)
    )
  end

  it 'delegates supported intents to the executor' do
    payload = instance_double('InputPayload')

    handler.handle_menu_intent(:menu_select, payload)

    expect(executor.calls).to eq([[:menu_select, payload]])
  end

  it 'raises for unsupported intents' do
    expect { handler.handle_menu_intent(:unknown_intent) }.to raise_error(ArgumentError, /Unsupported menu intent/)
  end

  it 'enforces typed executor dependency' do
    expect do
      described_class.new(
        deps: described_class::Dependencies.new(intent_executor: Object.new, command_logger: logger)
      )
    end.to raise_error(ArgumentError, /intent_executor must implement/)
  end
end
