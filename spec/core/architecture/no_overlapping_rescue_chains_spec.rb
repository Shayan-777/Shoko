# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No overlapping rescue chains' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'forbids overlapping rescue classes after explicit re-raise in same rescue chain' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.overlapping_rescue_chain_offenders(
      lib_root:
    )

    expect(offenders).to eq([]),
                         "Overlapping rescue chains with explicit re-raise produce unreachable handlers:\n#{offenders.join("\n")}"
  end
end
