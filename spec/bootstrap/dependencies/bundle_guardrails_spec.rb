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

  it 'keeps service bundle roles explicitly segmented' do
    expect(deps_module::RuntimeBootstrapServiceBundle.members).to eq(%i[workflow rendering session_support])
    expect(deps_module::ReaderServiceBundle.members).to eq(%i[workflow rendering support])
    expect(deps_module::MenuServiceBundle.members).to eq(%i[workflow domain reader_runtime])
  end

  it 'keeps nested service bundles within the same 16-field budget' do
    nested_bundle_constants = %i[
      RuntimeBootstrapWorkflowBundle
      RuntimeBootstrapRenderingBundle
      RuntimeBootstrapSessionSupportBundle
      ReaderWorkflowServiceBundle
      ReaderRenderingServiceBundle
      ReaderSupportServiceBundle
      MenuWorkflowServiceBundle
      MenuDomainServiceBundle
      MenuReaderServiceBundle
    ]

    offenders = nested_bundle_constants.filter_map do |const_name|
      klass = deps_module.const_get(const_name)
      count = klass.members.length
      "#{const_name} (#{count})" if count > 16
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
