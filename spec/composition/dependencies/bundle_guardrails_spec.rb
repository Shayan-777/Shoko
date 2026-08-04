# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dependency bundles' do
  let(:deps_module) { Shoko::Adapters::Input::Controllers::Dependencies }

  def build_empty_record(klass)
    klass.new(**klass.members.to_h { |field| [field, nil] })
  end

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
    core = build_empty_record(deps_module::ReaderControllerCoreDependencies)
    state = build_empty_record(deps_module::ReaderControllerStateDependencies)
    runtime_boot = build_empty_record(deps_module::ReaderRuntimeBootDependencies)
    runtime_startup = build_empty_record(deps_module::ReaderRuntimeStartupDependencies)
    mouse_support = build_empty_record(deps_module::ReaderMouseDependencies)

    expect { core.validate! }.to raise_error(ArgumentError, /Missing required ReaderControllerCoreDependencies/)
    expect { state.validate! }.to raise_error(ArgumentError, /Missing required ReaderControllerStateDependencies/)
    expect { runtime_boot.validate! }.to raise_error(ArgumentError, /Missing required ReaderRuntimeBootDependencies/)
    expect { runtime_startup.validate! }.to raise_error(ArgumentError, /Missing required ReaderRuntimeStartupDependencies/)
    expect { mouse_support.validate! }.to raise_error(ArgumentError, /Missing required ReaderMouseDependencies/)
  end

  it 'keeps removed runtime composition dependency bundles deleted' do
    prefix = 'RuntimeComposition'
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
                         "Removed runtime composition dependency constants reappeared: #{offenders.join(', ')}"
  end

  it 'keeps the removed monolithic reader dependency bag deleted' do
    expect(deps_module.const_defined?(:ReaderControllerDependencies, false)).to be(false)
  end

  it 'rejects unknown keys in a direct dependency record builder' do
    klass = Shoko::Adapters::Input::Controllers::Menu::Controller::SupportDependencies

    expect do
      klass.build(notification_service: nil, clipboard_service: nil, logger: nil, loger: Object.new)
    end.to raise_error(ArgumentError, /Unknown SupportDependencies dependencies: :loger/)
  end

  it 'rejects unknown keys at grouped bundle boundaries' do
    klass = deps_module::UiControllerDependencies::Bundle

    expect do
      klass.build(unknown_controller: Object.new)
    end.to raise_error(ArgumentError, /Unknown Bundle dependencies: :unknown_controller/)
  end

  it 'projects validated grouped wiring into each child record' do
    groups = deps_module::StateControllerDependencies
    dependencies = groups::Bundle.build(
      **groups::SessionDependencies.members.to_h { |field| [field, Object.new] },
      **groups::DocumentDependencies.members.to_h { |field| [field, Object.new] },
      **groups::ServiceDependencies.members.to_h { |field| [field, Object.new] }
    )

    expect(dependencies.session.to_h.keys).to eq(groups::SessionDependencies.members)
    expect(dependencies.document.to_h.keys).to eq(groups::DocumentDependencies.members)
    expect(dependencies.services.to_h.keys).to eq(groups::ServiceDependencies.members)
  end
end
