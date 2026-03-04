# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::IntentExecutorBridge do
  let(:controller_class) do
    Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end
    end.tap do |klass|
      described_class::INTENT_DISPATCH.values.uniq.each do |method_name|
        klass.define_method(method_name) do |*args|
          @calls << [method_name, args]
        end
      end
    end
  end

  let(:controller) { controller_class.new }
  let(:bridge) { described_class.new(menu_controller: controller) }

  it 'dispatches supported intents to mapped controller methods with key payload' do
    payload = Struct.new(:key).new('x')

    bridge.execute(intent_symbol: :menu_select, payload: payload)

    expect(controller.calls).to include([:menu_select, ['x']])
  end

  it 'raises for unsupported intent symbols' do
    expect do
      bridge.execute(intent_symbol: :does_not_exist, payload: nil)
    end.to raise_error(ArgumentError, /Unsupported menu intent/)
  end

  it 'fails initialization when required controller methods are missing' do
    incomplete = Class.new.new

    expect do
      described_class.new(menu_controller: incomplete)
    end.to raise_error(ArgumentError, /missing dispatch methods/i)
  end
end
