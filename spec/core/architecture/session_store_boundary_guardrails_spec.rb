# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Session store boundary guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:files) { Dir[File.join(root, 'lib/shoko/application/**/*.rb')].sort }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  end

  it 'keeps migrated phase-3 application files off state-slice reader/writer ports' do
    forbidden_patterns = [
      /core\/ports\/outbound\/config_reader/,
      /core\/ports\/outbound\/ui_state_reader/,
      /core\/ports\/outbound\/reader_navigation_reader/,
      /core\/ports\/outbound\/sidebar_state_reader/,
      /core\/ports\/outbound\/menu_state_reader/,
      /core\/ports\/outbound\/pagination_state_writer/,
      /core\/ports\/outbound\/reader_state_writer/,
      /core\/ports\/outbound\/menu_state_writer/,
      /core\/ports\/outbound\/menu_workflow_state_writer/,
      /core\/ports\/outbound\/ui_loading_writer/,
      /core\/ports\/outbound\/render_state_writer/,
      /\bConfigReader\b/,
      /\bUiStateReader\b/,
      /\bReaderNavigationReader\b/,
      /\bSidebarStateReader\b/,
      /\bMenuStateReader\b/,
      /\bPaginationStateWriter\b/,
      /\bReaderStateWriter\b/,
      /\bMenuStateWriter\b/,
      /\bMenuWorkflowStateWriter\b/,
      /\bUiLoadingWriter\b/,
      /\bRenderStateWriter\b/
    ]

    offenders = files.filter_map do |path|
      content = non_comment_content(path)
      next unless forbidden_patterns.any? { |pattern| content.match?(pattern) }

      path.delete_prefix("#{root}/")
    end

    expect(offenders).to eq([]),
      "Application files still reference legacy state-slice ports:\n#{offenders.join("\n")}"
  end
end
