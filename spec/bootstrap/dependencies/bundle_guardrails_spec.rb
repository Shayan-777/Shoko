# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dependency bundles' do
  let(:deps_module) { Shoko::Adapters::Input::Controllers::Dependencies }

  it 'keeps bundle object field counts bounded' do
    bundle_constants = deps_module.constants.grep(/Bundle\z/).sort

    offenders = bundle_constants.filter_map do |const_name|
      klass = deps_module.const_get(const_name)
      next unless klass.respond_to?(:members)

      count = klass.members.length
      "#{const_name} (#{count})" if count > 16
    end

    expect(offenders).to eq([])
  end

  it 'requires mandatory reader dependency sets' do
    core = deps_module::ReaderControllerCoreDependencies.build
    state = deps_module::ReaderControllerStateDependencies.build
    runtime_boot = deps_module::ReaderRuntimeBootDependencies.build
    runtime_startup = deps_module::ReaderRuntimeStartupDependencies.build
    mouse_support = deps_module::MouseableReaderDependencies.build

    expect { core.validate! }.to raise_error(ArgumentError, /Missing required ReaderControllerCoreDependencies/)
    expect { state.validate! }.to raise_error(ArgumentError, /Missing required ReaderControllerStateDependencies/)
    expect { runtime_boot.validate! }.to raise_error(ArgumentError, /Missing required ReaderRuntimeBootDependencies/)
    expect { runtime_startup.validate! }.to raise_error(ArgumentError, /Missing required ReaderRuntimeStartupDependencies/)
    expect { mouse_support.validate! }.to raise_error(ArgumentError, /Missing required MouseableReaderDependencies/)
  end

  it 'keeps removed runtime bootstrap dependency bundles deleted' do
    prefix = 'RuntimeBootstrap'
    removed_constants = %w[
      ServiceBundle
      WorkflowBundle
      RenderingBundle
      SessionSupportBundle
      Dependencies
    ].map { |suffix| "#{prefix}#{suffix}".to_sym }

    offenders = removed_constants.select do |const_name|
      deps_module.const_defined?(const_name, false)
    end

    expect(offenders).to eq([]),
                         "Removed runtime bootstrap dependency constants reappeared: #{offenders.join(', ')}"
  end

  it 'keeps the removed monolithic reader dependency bag deleted' do
    expect(deps_module.const_defined?(:ReaderControllerDependencies, false)).to be(false)
  end

end
