# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Command bus guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:input_root) { File.join(root, 'lib', 'shoko', 'adapters', 'input') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'keeps semantic commands disjoint from intent command namespaces' do
    semantic = Shoko::Application::UseCases::CommandBus::SEMANTIC_COMMAND_REGISTRY.keys
    reader = Shoko::Application::UseCases::CommandBus::READER_INTENT_COMMAND_REGISTRY.keys
    menu = Shoko::Application::UseCases::CommandBus::MENU_INTENT_COMMAND_REGISTRY.keys

    overlaps = {
      semantic_reader: semantic & reader,
      semantic_menu: semantic & menu
    }.select { |_name, entries| entries.any? }

    expect(overlaps).to eq({}),
                        "Command symbols overlap across registries: #{overlaps.inspect}"
  end

  it 'routes shared reader/menu symbols through explicit shared intent symbols' do
    reader = Shoko::Application::UseCases::CommandBus::READER_INTENT_COMMAND_REGISTRY.keys
    menu = Shoko::Application::UseCases::CommandBus::MENU_INTENT_COMMAND_REGISTRY.keys
    shared = Shoko::Application::UseCases::CommandBus::SHARED_INTENT_SYMBOLS

    expected_shared = (
      Shoko::Core::Ports::Inbound::ReaderIntentHandler::INTENT_SYMBOLS &
      Shoko::Core::Ports::Inbound::MenuIntentHandler::INTENT_SYMBOLS
    ).sort

    expect(shared.sort).to eq(expected_shared)
    expect((reader & menu).sort).to eq([])
    expect(shared).not_to be_empty
  end

  it 'forbids legacy reflective passthrough command artifacts' do
    expect(Shoko::Application::UseCases::Commands.const_defined?(:ContextMethodCommand, false)).to eq(false)

    path = File.join(root, 'lib', 'shoko', 'application', 'use_cases', 'command_bus.rb')
    content = non_comment_content(path)

    expect(content).not_to include('PASSTHROUGH_COMMAND_SYMBOLS')
    expect(content).not_to include('ContextMethodCommand')
  end

  it 'requires intent commands to be referenced by input adapters' do
    files = Dir[File.join(input_root, '**', '*.rb')]
    intent_symbols =
      Shoko::Application::UseCases::CommandBus::READER_INTENT_COMMAND_REGISTRY.keys +
      Shoko::Application::UseCases::CommandBus::MENU_INTENT_COMMAND_REGISTRY.keys

    missing = intent_symbols.uniq.reject do |symbol|
      pattern = /\b#{Regexp.escape(symbol.to_s)}\b/
      files.any? { |path| non_comment_content(path).match?(pattern) }
    end

    expect(missing).to eq([]),
                         "Intent commands have no input-adapter references: #{missing.join(', ')}"
  end
end
