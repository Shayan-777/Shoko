# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::CommandBridge do
  describe '.command?' do
    it 'recognizes supported command symbols' do
      command_port = instance_double('CommandPort')
      allow(command_port).to receive(:command_exists?).with(:next_page).and_return(true)
      allow(command_port).to receive(:command_exists?).with(:menu_up).and_return(true)
      allow(command_port).to receive(:command_exists?).with(:unknown_action).and_return(false)
      context = Struct.new(:command_port).new(command_port)

      expect(described_class.command?(:next_page, context)).to be(true)
      expect(described_class.command?(:menu_up, context)).to be(true)
      expect(described_class.command?(:unknown_action, context)).to be(false)
    end
  end

  describe '.symbol_to_command' do
    it 'builds commands via explicit command_port on context' do
      command = instance_double('Command')
      command_port = instance_double('CommandPort', build_command: command, command_exists?: true)
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

    it 'returns nil when command_port does not expose the symbol' do
      command_port = instance_double('CommandPort', command_exists?: false)
      context = Struct.new(:command_port).new(command_port)

      result = described_class.symbol_to_command(:unknown_action, context)

      expect(result).to be_nil
    end
  end
end
