# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::CommandBus do
  subject(:command_bus) { described_class.new }

  it 'builds semantic commands from explicit registry entries' do
    command = command_bus.build_command(:next_page)

    expect(command).to be_a(Shoko::Application::UseCases::Commands::NavigationCommand)
  end

  it 'builds grouped reader application commands for adapter actions' do
    context_class = Class.new do
      include Shoko::Core::Ports::Inbound::IntentDispatchContext
      include Shoko::Core::Ports::Inbound::ReaderLifecycleCommandContext

      attr_reader :called

      def quit_to_menu
        @called = true
        :handled
      end

      def rebuild_pagination
        raise 'not used'
      end

      def invalidate_pagination_cache
        raise 'not used'
      end

      def quit_application
        raise 'not used'
      end

      def command_bus
        nil
      end

      def command_logger
        nil
      end
    end
    context = context_class.new

    command = command_bus.build_command(:quit_to_menu)

    expect(command).to be_a(Shoko::Application::UseCases::Commands::Reader::LifecycleCommand)
    expect(command.execute(context)).to eq(:handled)
    expect(context.called).to eq(true)
  end

  it 'executes reader key-bearing commands with typed payload' do
    context_class = Class.new do
      include Shoko::Core::Ports::Inbound::IntentDispatchContext
      include Shoko::Core::Ports::Inbound::ReaderAnnotationEditorCommandContext

      attr_reader :received_key

      def annotation_editor_insert_char_if_printable(key = nil)
        @received_key = key
        :handled
      end

      def annotation_editor_backspace
        raise 'not used'
      end

      def annotation_editor_cancel
        raise 'not used'
      end

      def annotation_editor_enter
        raise 'not used'
      end

      def annotation_editor_move_down
        raise 'not used'
      end

      def annotation_editor_move_left
        raise 'not used'
      end

      def annotation_editor_move_right
        raise 'not used'
      end

      def annotation_editor_move_up
        raise 'not used'
      end

      def annotation_editor_save
        raise 'not used'
      end

      def annotation_editor_spellcheck
        raise 'not used'
      end

      def command_bus
        nil
      end

      def command_logger
        nil
      end
    end
    context = context_class.new

    expect(command_bus.execute_command(:annotation_editor_insert_char_if_printable, context, key: 'q')).to eq(:handled)
    expect(context.received_key).to eq('q')
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
