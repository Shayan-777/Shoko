# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Command dispatch guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'forbids dynamic dispatch internals in command-path classes' do
    files = [
      File.join(lib_root, 'application', 'use_cases', 'command_bus.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'reader_gateway_command.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'menu_gateway_command.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'shared_gateway_command.rb'),
      File.join(lib_root, 'adapters', 'input', 'commands.rb'),
    ]

    pattern = /\bpublic_send\b|\bsend\s*\(|\brespond_to\?\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "Dynamic dispatch internals remain in command-path files:\n#{offenders.join("\n")}"
  end

  it 'forbids silent broad rescue patterns in command-path classes' do
    files = [
      File.join(lib_root, 'application', 'use_cases', 'command_bus.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'base_command.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'reader_gateway_command.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'menu_gateway_command.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'shared_gateway_command.rb'),
      File.join(lib_root, 'adapters', 'input', 'commands.rb'),
    ]

    silent_broad_rescue = /rescue\s+StandardError(?:\s*=>\s*\w+)?\s*\n\s*(?:nil|:pass)\b/m
    offenders = files.select { |path| non_comment_content(path).match?(silent_broad_rescue) }

    expect(offenders).to eq([]),
                         "Silent broad rescue patterns remain in command-path files:\n#{offenders.join("\n")}"
  end

  it 'forbids references to removed ContextMethodCommand artifacts' do
    removed_path = File.join(lib_root, 'application', 'use_cases', 'commands', 'context_method_command.rb')
    expect(File.exist?(removed_path)).to eq(false)

    files = Dir[File.join(root, '{lib,spec,docs}', '**', '*.{rb,md}')] + [File.join(root, 'README.md')]
    files = files.reject { |path| path.include?(File.join('spec', 'core', 'architecture')) }
    offenders = files.select { |path| non_comment_content(path).include?('ContextMethodCommand') }

    expect(offenders).to eq([]),
                         "ContextMethodCommand references still exist:\n#{offenders.join("\n")}"
  end

  it 'forbids adapter references to Application::Services::DocumentPathResolver' do
    files = Dir[File.join(lib_root, 'adapters', '**', '*.rb')]
    offenders = files.select do |path|
      content = non_comment_content(path)
      content.include?('Application::Services::DocumentPathResolver') ||
        content.include?('application/services/document_path_resolver')
    end

    expect(offenders).to eq([]),
                         "Adapters still reference application DocumentPathResolver:\n#{offenders.join("\n")}"
  end
end
