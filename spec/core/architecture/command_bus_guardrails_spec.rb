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

  it 'keeps semantic and passthrough command namespaces disjoint' do
    semantic = Shoko::Application::UseCases::CommandBus::SEMANTIC_COMMAND_REGISTRY.keys
    passthrough = Shoko::Application::UseCases::CommandBus::PASSTHROUGH_COMMAND_SYMBOLS
    overlap = semantic & passthrough

    expect(overlap).to eq([]),
                         "Command symbols are duplicated across semantic and passthrough registries: #{overlap.join(', ')}"
  end

  it 'forbids duplicate passthrough command entries' do
    passthrough = Shoko::Application::UseCases::CommandBus::PASSTHROUGH_COMMAND_SYMBOLS
    duplicates = passthrough.group_by(&:itself).select { |_symbol, entries| entries.length > 1 }.keys

    expect(duplicates).to eq([]), "Duplicate passthrough command symbols found: #{duplicates.join(', ')}"
  end

  it 'requires passthrough commands to be referenced by input adapters' do
    files = Dir[File.join(input_root, '**', '*.rb')]
    passthrough = Shoko::Application::UseCases::CommandBus::PASSTHROUGH_COMMAND_SYMBOLS

    missing = passthrough.reject do |symbol|
      pattern = /\b#{Regexp.escape(symbol.to_s)}\b/
      files.any? { |path| non_comment_content(path).match?(pattern) }
    end

    expect(missing).to eq([]),
                         "Passthrough commands have no input-adapter references: #{missing.join(', ')}"
  end
end
