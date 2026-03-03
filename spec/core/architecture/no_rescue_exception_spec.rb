# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No Exception rescues in runtime code' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'forbids rescue Exception in lib/shoko runtime sources' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.exception_rescue_offenders(
      lib_root:
    )

    expect(offenders).to eq([]),
                         "rescue Exception is not allowed in runtime code:\n#{offenders.join("\n")}" # rubocop:disable Layout/LineLength
  end
end
