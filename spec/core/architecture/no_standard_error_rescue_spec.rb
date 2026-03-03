# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No StandardError rescues in runtime code' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'forbids rescue StandardError in lib/shoko runtime sources' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.standard_error_rescue_offenders(
      lib_root:
    )

    expect(offenders).to eq([]),
                         "rescue StandardError is not allowed in runtime code:\n#{offenders.join("\n")}"
  end
end
