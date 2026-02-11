# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::CommandBridge do
  describe '.command?' do
    it 'recognizes supported command symbols' do
      expect(described_class.command?(:next_page)).to be(true)
      expect(described_class.command?(:menu_up)).to be(true)
      expect(described_class.command?(:unknown_action)).to be(false)
    end
  end

  describe '.symbol_to_command' do
    it 'builds commands via explicit command_port on context' do
      command = instance_double('Command')
      command_port = instance_double('CommandPort', build_command: command)
      context = Struct.new(:command_port).new(command_port)

      result = described_class.symbol_to_command(:next_page, context)

      expect(result).to be(command)
    end

    it 'does not resolve command_port from container/dependencies' do
      container = instance_double('DependencyContainer')
      allow(container).to receive(:resolve)
      context = Struct.new(:container).new(container)

      result = described_class.symbol_to_command(:next_page, context)

      expect(result).to be_nil
      expect(container).not_to have_received(:resolve)
    end
  end
end
