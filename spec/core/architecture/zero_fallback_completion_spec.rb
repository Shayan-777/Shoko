# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Zero fallback completion guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:application_root) { File.join(lib_root, 'application') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  it 'forbids bare rescue assignment syntax across runtime code' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(/\brescue\s*=>\s*\w+/) }

    expect(offenders).to eq([]), "Found bare rescue assignment patterns:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end

  it 'forbids inline rescue expressions across runtime code' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = []
    files.each do |path|
      File.readlines(path).each_with_index do |line, index|
        next unless line.include?(' rescue ')

        stripped = line.strip
        next if stripped.start_with?('#')
        next if stripped.start_with?('rescue')

        offenders << "#{rel(path)}:#{index + 1}"
      end
    end

    expect(offenders).to eq([]), "Found inline rescue expressions:\n#{offenders.join("\n")}"
  end

  it 'forbids controller loopback in application intent handlers' do
    files = [
      File.join(application_root, 'use_cases', 'reader_intent_handler.rb'),
      File.join(application_root, 'use_cases', 'menu_intent_handler.rb')
    ]
    pattern = /@reader_controller\.|@menu_controller\.|reader_controller:|menu_controller:/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]), "Application intent handlers still contain controller loopback:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end

  it 'forbids bootstrap session-context coupling in application layer' do
    files = Dir[File.join(application_root, '**', '*.rb')]
    pattern = /ReaderSessionContext|MenuSessionContext|reader_session_context|menu_session_context/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "Application layer still references removed bootstrap session context:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end

  it 'enforces symbol-only direct intent dispatch contract' do
    dispatcher_path = File.join(lib_root, 'adapters', 'input', 'dispatcher.rb')
    reader_handler_path = File.join(application_root, 'use_cases', 'reader_intent_handler.rb')
    menu_handler_path = File.join(application_root, 'use_cases', 'menu_intent_handler.rb')

    dispatcher_content = non_comment_content(dispatcher_path)
    reader_handler_content = non_comment_content(reader_handler_path)
    menu_handler_content = non_comment_content(menu_handler_path)

    expect(dispatcher_content).to include('binding.is_a?(Symbol)')
    expect(dispatcher_content).not_to match(/\bexecute_proc\b|\bexecute_object\b|\bexecutable_command\?\b/)
    expect(reader_handler_content).to include('intent_symbol.to_sym')
    expect(menu_handler_content).to include('intent_symbol.to_sym')
  end
end
