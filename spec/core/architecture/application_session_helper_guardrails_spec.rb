# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Application session helper guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:reader_builder_paths) do
    Dir[
      File.join(
        root,
        'lib',
        'shoko',
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
      root,
      'lib',
      'shoko',
      'composition',
      'container_factory',
      'controller_composition',
      'menu_builder.rb'
    )
  end

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  end

  it 'wires ReaderIntentHandler through ReaderSessionStore instead of adapter-local reader helpers' do
    content = reader_builder_paths.map { |path| non_comment_content(path) }.join("\n")

    expect(content).to match(/ReaderIntentHandler\.new\([^)]*reader_session_store:/m),
                       'Reader intent handler must be wired with reader_session_store in reader_builder/'
    expect(content).not_to match(/ReaderIntentHandler\.new\([^)]*reader_state_reader:/m),
                           'Reader intent handler must not receive reader_state_reader in reader_builder/'
  end

  it 'wires MenuIntentHandler through MenuSessionStore instead of adapter-local session helpers' do
    content = non_comment_content(menu_builder_path)

    expect(content).to match(/MenuIntentHandler\.new\([^)]*menu_session_store:/m),
                       "Menu intent handler must be wired with menu_session_store: #{menu_builder_path}"
    expect(content).not_to match(/MenuIntentHandler\.new\([^)]*menu_state_reader:/m),
                           "Menu intent handler must not receive menu_state_reader: #{menu_builder_path}"
    expect(content).not_to match(/MenuIntentHandler\.new\([^)]*menu_session_mutator:/m),
                           "Menu intent handler must not receive menu_session_mutator: #{menu_builder_path}"
  end
end
