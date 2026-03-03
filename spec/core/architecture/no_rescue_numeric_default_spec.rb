# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No rescue numeric defaults' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'forbids rescue branches that default to numeric literals' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.numeric_default_rescue_offenders(
      lib_root:
    )

    expect(offenders).to eq([]),
                         "Rescue branches must not hide failures with numeric defaults:\n#{offenders.join("\n")}"
  end
end
