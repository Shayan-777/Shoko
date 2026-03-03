# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No implicit NullRuntimeConfig fallback expressions' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'forbids || NullRuntimeConfig.instance fallback expressions in runtime code' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.implicit_null_runtime_config_offenders(
      lib_root:
    )

    expect(offenders).to eq([]),
                         "Implicit NullRuntimeConfig fallback expressions are not allowed:\n#{offenders.join("\n")}" # rubocop:disable Layout/LineLength
  end
end
