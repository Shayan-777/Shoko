# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'StandardError rescue translation in runtime code' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'requires rescue StandardError branches to fail fast with explicit translation/raising' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.standard_error_rescue_without_translation_offenders(
      lib_root:
    )

    expect(offenders).to eq([]),
                         "rescue StandardError must immediately raise/translate failures:\n#{offenders.join("\n")}"
  end
end
