# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Direct intent guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'forbids command-bus and context-command artifacts across lib/spec/docs' do
    removed_terms = %w[
      CommandBus
      IntentDispatchContext
      InputCommandPayload
      ReaderNavigationCommandContext
      ReaderBookmarkCommandContext
      MenuNavigationCommandContext
      MenuBrowseCommandContext
      MenuSearchCommandContext
      MenuDownloadCommandContext
      MenuDictionaryCommandContext
      MenuAnnotationCommandContext
      MenuSettingsCommandContext
      MenuLifecycleCommandContext
      ReaderOverlayCommandContext
      ReaderDictionaryCommandContext
      ReaderSearchCommandContext
      ReaderAnnotationEditorCommandContext
      ReaderLifecycleCommandContext
      Adapters::Input::Commands
      application/use_cases/commands/
    ]

    files = Dir[File.join(root, '{lib,spec,docs}', '**', '*.{rb,md}')] + [File.join(root, 'README.md')]
    files = files.reject { |path| path.include?(File.join('spec', 'core', 'architecture')) }
    offenders = files.select do |path|
      content = non_comment_content(path)
      removed_terms.any? { |term| content.include?(term) }
    end

    expect(offenders).to eq([]),
                         "Legacy command-path references remain:\n#{offenders.join("\n")}"
  end

  it 'forbids deleted command-path files from reappearing' do
    removed_files = [
      File.join(lib_root, 'adapters', 'input', 'commands.rb'),
      File.join(lib_root, 'application', 'use_cases', 'command_bus.rb'),
      File.join(lib_root, 'core', 'ports', 'inbound', 'command_bus.rb'),
      File.join(lib_root, 'core', 'ports', 'inbound', 'intent_dispatch_context.rb'),
      File.join(lib_root, 'core', 'ports', 'inbound', 'input_command_payload.rb'),
      File.join(lib_root, 'core', 'ports', 'inbound', 'menu_command_contexts.rb'),
      File.join(lib_root, 'core', 'ports', 'inbound', 'reader_command_contexts.rb'),
      File.join(lib_root, 'core', 'ports', 'inbound', 'reader_navigation_command_context.rb'),
      File.join(lib_root, 'core', 'ports', 'inbound', 'reader_bookmark_command_context.rb'),
    ]

    offenders = removed_files.select { |path| File.exist?(path) }
    expect(offenders).to eq([]),
                         "Deleted command-path files reappeared:\n#{offenders.join("\n")}"
  end
end
