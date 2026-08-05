# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe 'Application port boundaries' do
  let(:lib_root) { File.expand_path('../../../lib/shoko', __dir__) }
  let(:ports_root) { File.join(lib_root, 'application/ports') }

  def interface_ports
    ObjectSpace.each_object(Module).select do |mod|
      next false unless mod.instance_of?(Module)

      name = Module.instance_method(:name).bind_call(mod).to_s
      next false unless name.start_with?('Shoko::Application::Ports::')

      mod.instance_methods(false).any? do |method|
        location = mod.instance_method(method).source_location&.first
        location&.start_with?(ports_root)
      end
    end
  end

  def production_implementers(port)
    ObjectSpace.each_object(Module).select do |candidate|
      name = Module.instance_method(:name).bind_call(candidate).to_s
      !name.empty? && !name.start_with?('Shoko::Application::Ports::') && candidate.ancestors.include?(port)
    end
  end

  it 'keeps port files in the inbound, outbound, or internal ownership groups' do
    entries = Dir[File.join(ports_root, '*')]
    unexpected = entries.reject do |path|
      File.directory?(path) && %w[inbound outbound internal].include?(File.basename(path))
    end
    expect(unexpected).to be_empty
  end

  it 'keeps an explicit reviewed inventory for every port file' do
    inventory_path = File.expand_path('../../../docs/architecture/port-inventory.yml', __dir__)
    groups = YAML.safe_load_file(inventory_path).fetch('groups')
    reviewed = groups.values.flat_map { |group| group.fetch('ports') }
    groups.each_value { |group| expect(group.fetch('rationale').to_s.strip).not_to be_empty }
    actual = Dir[File.join(ports_root, '**', '*.rb')].map { |path| path.delete_prefix("#{ports_root}/") }

    expect(reviewed).to match_array(actual)
    expect(reviewed.uniq.length).to eq(reviewed.length)
  end

  it 'requires every nominal interface to have a production implementer in the correct layer' do
    ports = interface_ports
    expect(ports).not_to be_empty

    offenders = ports.filter_map do |port|
      implementers = production_implementers(port)
      next "#{port.name}: no production implementer" if implementers.empty?

      names = implementers.filter_map(&:name)
      if port.name.include?('::Outbound::') && names.none? { |name| name.start_with?('Shoko::Adapters::') }
        "#{port.name}: outbound port has no adapter implementation"
      elsif port.name.include?('::Internal::') && names.any? { |name| name.start_with?('Shoko::Adapters::') }
        "#{port.name}: internal port is implemented by an adapter"
      end
    end
    expect(offenders).to be_empty, offenders.join("\n")
  end

  it 'keeps menu intent actions exactly aligned with the inbound contract' do
    expected = Shoko::Application::Ports::Inbound::MenuIntentHandler::INTENT_SYMBOLS.sort
    groups = Shoko::Application::UseCases::Menu::Actions.constants(false).filter_map do |name|
      group = Shoko::Application::UseCases::Menu::Actions.const_get(name)
      group::SUPPORTED_INTENTS if group.const_defined?(:SUPPORTED_INTENTS, false)
    end
    expect(groups.flatten.uniq.sort).to eq(expected)
  end

  it 'keeps reader intent actions exactly aligned with the inbound contract' do
    expected = Shoko::Application::Ports::Inbound::ReaderIntentHandler::INTENT_SYMBOLS.sort
    groups = Shoko::Application::UseCases::Reader::Actions.constants(false).filter_map do |name|
      group = Shoko::Application::UseCases::Reader::Actions.const_get(name)
      group::SUPPORTED_INTENTS if group.const_defined?(:SUPPORTED_INTENTS, false)
    end
    expect(groups.flatten.uniq.sort).to eq(expected)
  end
end
