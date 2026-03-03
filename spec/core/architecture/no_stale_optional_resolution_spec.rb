# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No stale optional resolution scaffolding' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'forbids optional ternary resolution branches that resolve identically' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.stale_optional_resolution_offenders(
      lib_root:
    )

    expect(offenders).to eq([]),
                         "Optional resolution scaffolding remains with identical branches:\n#{offenders.join("\n")}"
  end
end
