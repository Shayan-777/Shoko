# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dependency bundles' do
  let(:deps_module) { Shoko::Adapters::Input::Controllers::Dependencies }

  it 'keeps bundle object field counts bounded' do
    bundle_constants = %i[
      RuntimeBootstrapCoreBundle
      RuntimeBootstrapServiceBundle
      RuntimeBootstrapStorageBundle
      RuntimeBootstrapSessionBundle
      RuntimeBootstrapPlatformBundle
      ReaderCoreBundle
      ReaderServiceBundle
      ReaderSessionBundle
      ReaderRuntimeBundle
      ReaderPlatformBundle
      MenuCoreBundle
      MenuServiceBundle
      MenuSessionBundle
      MenuPlatformBundle
    ]

    offenders = bundle_constants.filter_map do |const_name|
      klass = deps_module.const_get(const_name)
      count = klass.members.length
      "#{const_name} (#{count})" if count > 28
    end

    expect(offenders).to eq([])
  end

  it 'requires mandatory reader controller dependencies' do
    deps = deps_module::ReaderControllerDependencies.build
    expect { deps.validate! }.to raise_error(ArgumentError, /Missing required reader dependencies/)
  end

  it 'requires mandatory runtime bootstrap dependencies' do
    deps = deps_module::RuntimeBootstrapDependencies.build
    expect { deps.validate! }.to raise_error(ArgumentError, /Missing required runtime bootstrap dependencies/)
  end

  it 'exposes runtime bootstrap facades for state/workflow/rendering' do
    deps = deps_module::RuntimeBootstrapDependencies.build

    expect(deps.state_facade).to respond_to(:reader_state_reader)
    expect(deps.workflow_facade).to respond_to(:navigation_service)
    expect(deps.rendering_facade).to respond_to(:rendering_factory)
    expect(deps.persistence_facade).to respond_to(:pagination_coordinator_factory)
  end

  it 'requires mandatory menu controller dependencies' do
    deps = deps_module::MenuControllerDependencies.build
    expect { deps.validate! }.to raise_error(ArgumentError, /Missing required menu dependencies/)
  end

  it 'exposes reader controller facades for state/workflow/rendering/lifecycle' do
    deps = deps_module::ReaderControllerDependencies.build

    expect(deps.state_facade).to respond_to(:reader_state_reader)
    expect(deps.workflow_facade).to respond_to(:navigation_service)
    expect(deps.rendering_facade).to respond_to(:wrapping_service)
    expect(deps.lifecycle_facade).to respond_to(:reader_lifecycle_factory)
  end
end
