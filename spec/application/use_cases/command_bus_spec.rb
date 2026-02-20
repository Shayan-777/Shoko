# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::CommandBus do
  subject(:command_bus) { described_class.new }

  it 'builds semantic commands from explicit registry entries' do
    command = command_bus.build_command(:next_page)

    expect(command).to be_a(Shoko::Application::UseCases::Commands::NavigationCommand)
  end

  it 'builds whitelisted passthrough commands for adapter actions' do
    context = Class.new do
      attr_reader :called

      def quit_to_menu
        @called = true
        :handled
      end
    end.new

    command = command_bus.build_command(:quit_to_menu)

    expect(command).to be_a(Shoko::Application::UseCases::Commands::ContextMethodCommand)
    expect(command.execute(context)).to eq(:handled)
    expect(context.called).to eq(true)
  end

  it 'rejects unknown symbols outside the command whitelist' do
    expect(command_bus.command_exists?(:unknown_command)).to eq(false)
    expect(command_bus.build_command(:unknown_command)).to be_nil
    expect(command_bus.execute_command(:unknown_command, Object.new)).to be_nil
  end
end
