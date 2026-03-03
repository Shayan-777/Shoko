# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No bare string raises in runtime code' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  it 'forbids raise with string literals in lib/shoko runtime sources' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.bare_string_raise_offenders(
      lib_root:
    )

    expect(offenders).to eq([]),
                         "raise with string literal is not allowed in runtime code:\n#{offenders.join("\n")}" # rubocop:disable Layout/LineLength
  end
end
