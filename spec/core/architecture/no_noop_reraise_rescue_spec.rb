# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No no-op re-raise rescues' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:roots) do
    [
      File.join(lib_root, 'application'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', 'actions'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'reader')
    ]
  end

  it 'forbids rescue branches that only re-raise without translation or context' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.no_op_reraise_rescue_offenders(
      lib_root:,
      roots:
    )

    expect(offenders).to eq([]),
                         "No-op rescue re-raises must be removed:\n#{offenders.join("\n")}"
  end
end
