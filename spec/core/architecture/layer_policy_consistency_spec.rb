# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Layer policy consistency' do
  it 'keeps adapters isolated from application dependencies' do
    expect(SpecSupport::Architecture::LayerPolicy.allowed_targets_for('adapters'))
      .not_to include('application')
  end

  it 'forces architecture specs to use the shared layer policy helper' do
    files = [
      File.expand_path('layer_dependency_spec.rb', __dir__),
      File.expand_path('strict_hexagonal_wiring_spec.rb', __dir__),
    ]
    offenders = files.reject { |path| File.read(path).include?('SpecSupport::Architecture::LayerPolicy') }

    expect(offenders).to be_empty,
                             "Layer boundary specs must use shared policy helper:\n#{offenders.sort.join("\n")}"
  end
end
