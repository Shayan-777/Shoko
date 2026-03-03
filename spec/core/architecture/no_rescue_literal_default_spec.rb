# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No rescue literal defaults' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'forbids fallback literal defaults directly after rescue branches' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.fallback_literal_rescue_offenders(
      lib_root:
    )

    expect(offenders).to eq([]),
                         "Rescue branches must fail fast instead of returning literal defaults:\n#{offenders.join("\n")}"
  end
end
