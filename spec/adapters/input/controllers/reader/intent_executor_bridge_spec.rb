# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::IntentExecutorBridge do
  let(:controller_class) do
    Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end
    end.tap do |klass|
      described_class::INTENT_DISPATCH.values.map(&:first).uniq.each do |method_name|
        klass.define_method(method_name) do |*args|
          @calls << [method_name, args]
        end
      end
    end
  end

  let(:controller) { controller_class.new }
  let(:bridge) { described_class.new(reader_controller: controller) }

  it 'dispatches key-bearing intents with payload key' do
    payload = Struct.new(:key).new('k')

    bridge.execute(intent_symbol: :dictionary_insert_char_if_printable, payload: payload)

    expect(controller.calls).to include([:dictionary_insert_char_if_printable, ['k']])
  end

  it 'dispatches no-arg intents without payload key' do
    payload = Struct.new(:key).new('ignored')

    bridge.execute(intent_symbol: :show_help, payload: payload)

    expect(controller.calls).to include([:show_help, []])
  end

  it 'raises for unsupported intent symbols' do
    expect do
      bridge.execute(intent_symbol: :does_not_exist, payload: nil)
    end.to raise_error(ArgumentError, /Unsupported reader intent/)
  end

  it 'fails initialization when required controller methods are missing' do
    incomplete = Class.new.new

    expect do
      described_class.new(reader_controller: incomplete)
    end.to raise_error(ArgumentError, /missing dispatch methods/i)
  end
end
