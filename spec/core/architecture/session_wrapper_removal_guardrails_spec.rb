# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Session wrapper removal guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:files) do
    Dir[File.join(root, 'lib/**/*.rb')].concat(Dir[File.join(root, 'spec/**/*.rb')]).sort
  end

  def scan_targets
    files.reject do |path|
      path.end_with?('/session_wrapper_removal_guardrails_spec.rb') ||
        path.end_with?('/session_store_boundary_guardrails_spec.rb') ||
        path.end_with?('/docs/cleanup-plan.md')
    end
  end

  it 'keeps removed session wrapper classes and registrations out of the repo' do
    forbidden_patterns = [
      /\bConfigView\b/,
      /\bReaderSessionView\b/,
      /\bMenuSessionView\b/,
      /\bReaderUiStateView\b/,
      /\bconfig_view\b/,
      /\breader_session_view\b/,
      /\bmenu_session_view\b/,
      /\breader_ui_state_view\b/
    ]

    offenders = scan_targets.filter_map do |path|
      content = File.read(path)
      next unless forbidden_patterns.any? { |pattern| content.match?(pattern) }

      path.delete_prefix("#{root}/")
    end

    expect(offenders).to eq([]),
      "Files still reference removed session wrappers:\n#{offenders.join("\n")}"
  end
end
