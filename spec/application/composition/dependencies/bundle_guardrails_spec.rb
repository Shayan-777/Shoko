# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dependency bundles' do
  let(:deps_module) { Shoko::Application::Composition::Dependencies }

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

  it 'requires mandatory menu controller dependencies' do
    deps = deps_module::MenuControllerDependencies.build
    expect { deps.validate! }.to raise_error(ArgumentError, /Missing required menu dependencies/)
  end
end
