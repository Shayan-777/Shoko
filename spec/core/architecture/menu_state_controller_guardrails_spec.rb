# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Menu state controller guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:state_controller_path) { File.join(root, 'lib', 'shoko', 'adapters', 'input', 'controllers', 'menu', 'state_controller.rb') }
  let(:content) { File.read(state_controller_path) }

  it 'forbids compatibility shim classes' do
    forbidden = %w[NullWorkflow NullProgressPresenter LegacyReaderLaunchService]
    offenders = forbidden.select { |name| content.match?(/\bclass #{Regexp.escape(name)}\b/) }

    expect(offenders).to eq([]), "Compatibility shims reintroduced in menu state controller: #{offenders.join(', ')}"
  end

  it 'forbids fallback branches that bypass injected factories' do
    forbidden_snippets = [
      'LegacyReaderLaunchService.new',
      'NullWorkflow.new',
      'NullProgressPresenter.new',
      'if @reader_launch_service_factory.respond_to?(:call)',
      'unless @download_workflow_factory.respond_to?(:call)',
      'unless @dictionary_workflow_factory.respond_to?(:call)',
      'unless @annotation_workflow_factory.respond_to?(:call)',
    ]
    offenders = forbidden_snippets.select { |snippet| content.include?(snippet) }

    expect(offenders).to eq([]), "Fallback wiring patterns reintroduced in menu state controller: #{offenders.join(', ')}"
  end
end
