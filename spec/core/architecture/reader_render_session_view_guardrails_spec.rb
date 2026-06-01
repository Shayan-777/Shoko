# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reader render session-view guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:files) do
    %w[
      lib/shoko/composition/container_factory.rb
      lib/shoko/composition/container_factory/controller_composition/reader_builder.rb
      lib/shoko/composition/container_factory/controller_composition/menu_builder.rb
    ].map { |path| File.join(root, path) }
  end

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  end

  it 'keeps the reader/menu composition render slice off legacy read-port resolutions' do
    forbidden_patterns = [
      /resolve\(:config_reader\)/,
      /resolve\(:reader_state_reader\)/,
      /resolve\(:reader_navigation_reader\)/,
      /resolve\(:ui_state_reader\)/,
      /resolve\(:sidebar_state_reader\)/,
      /resolve\(:menu_state_reader\)/,
    ]

    offenders = files.filter_map do |path|
      content = non_comment_content(path)
      next unless forbidden_patterns.any? { |pattern| content.match?(pattern) }

      path.delete_prefix("#{root}/")
    end

    expect(offenders).to eq([]),
                         "Reader render/output composition slice still resolves legacy read ports:\n#{offenders.join("\n")}"
  end

  it 'wires reader runtime assembler ui/render consumers to the broad reader state projection' do
    runtime_files = Dir[
      File.join(
        root,
        'lib',
        'shoko',
        'composition',
        'container_factory',
        'controller_composition',
        'reader_runtime_assembler',
        '**',
        '*.rb'
      )
    ]
    forbidden_patterns = [
      /reader_state_reader:\s*(?:context|runtime_context)\.state\.reader_session_store/,
      /reader_state:\s*(?:context|runtime_context)\.state\.reader_session_store/,
      /sidebar_state:\s*(?:context|runtime_context)\.state\.reader_session_store/,
    ]

    offenders = runtime_files.filter_map do |path|
      content = non_comment_content(path)
      next unless forbidden_patterns.any? { |pattern| content.match?(pattern) }

      path.delete_prefix("#{root}/")
    end

    expect(offenders).to eq([]),
                         "Reader runtime assembler still wires session-only state into UI/render consumers:\n#{offenders.join("\n")}"
  end
end
