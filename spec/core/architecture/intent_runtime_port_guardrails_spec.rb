# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Intent runtime port guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:application_use_cases_root) { File.join(lib_root, 'application', 'use_cases') }
  let(:reader_builder_paths) do
    Dir[
      File.join(
        lib_root,
        'composition',
        'container_factory',
        'controller_composition',
        'reader_builder',
        '*.rb'
      )
    ]
  end
  let(:menu_builder_path) do
    File.join(
      lib_root,
      'composition',
      'container_factory',
      'controller_composition',
      'menu_builder.rb'
    )
  end

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  end

  it 'keeps the legacy intent runtime facade ports deleted' do
    forbidden = [
      File.join(lib_root, 'core', 'ports', 'outbound', 'reader_intent_runtime.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'menu_intent_runtime.rb'),
    ]

    offenders = forbidden.select { |path| File.exist?(path) }
    expect(offenders).to eq([]),
                         "Legacy intent runtime facade ports reappeared:\n#{offenders.join("\n")}"
  end

  it 'forbids use-case layer references to legacy runtime facades' do
    files = Dir[File.join(application_use_cases_root, '**', '*.rb')]
    pattern = /\b(reader_runtime|menu_runtime|ReaderIntentRuntime|MenuIntentRuntime)\b/

    offenders = files.select { |path| non_comment_content(path).match?(pattern) }
    expect(offenders).to eq([]),
                         "Use-case layer still references legacy runtime facades:\n#{offenders.join("\n")}"
  end

  it 'wires ReaderIntentHandler through capability ports instead of reader_runtime:' do
    content = reader_builder_paths.map { |path| non_comment_content(path) }.join("\n")

    expect(content).to match(/ReaderIntentHandler\.new\([^)]*reader_display_control:/m),
                       'Reader intent handler must be wired with capability ports in reader_builder/'
    expect(content).to match(/ReaderIntentHandler\.new\([^)]*application_exit_control:/m),
                       'Reader intent handler must receive application_exit_control in reader_builder/'
    expect(content).not_to match(/ReaderIntentHandler\.new\([^)]*reader_runtime:/m),
                           'Reader intent handler must not receive reader_runtime in reader_builder/'
  end

  it 'wires MenuIntentHandler through capability ports instead of menu_runtime:' do
    content = non_comment_content(menu_builder_path)

    expect(content).to match(/MenuIntentHandler\.new\([^)]*menu_mode_control:/m),
                       "Menu intent handler must be wired with menu_mode_control: #{menu_builder_path}"
    expect(content).to match(/MenuIntentHandler\.new\([^)]*application_exit_control:/m),
                       "Menu intent handler must receive application_exit_control: #{menu_builder_path}"
    expect(content).not_to match(/MenuIntentHandler\.new\([^)]*menu_runtime:/m),
                           "Menu intent handler must not receive menu_runtime: #{menu_builder_path}"
  end
end
