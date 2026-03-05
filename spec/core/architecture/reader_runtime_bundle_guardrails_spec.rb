# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reader runtime bundle guardrails' do
  it 'keeps runtime bundle field counts bounded' do
    bundles = {
      Shoko::Bootstrap::ContainerFactory::ControllerComposition::ReaderRuntimeAssembler::SessionBundle => 12,
      Shoko::Bootstrap::ContainerFactory::ControllerComposition::ReaderRuntimeAssembler::ServiceBundle => 25,
      Shoko::Bootstrap::ContainerFactory::ControllerComposition::ReaderRuntimeAssembler::UiBundle => 2,
      Shoko::Bootstrap::ContainerFactory::ControllerComposition::ReaderRuntimeAssembler::PersistenceBundle => 4,
      Shoko::Bootstrap::ContainerFactory::ControllerComposition::ReaderRuntimeAssembler::RuntimeContext => 6,
    }

    offenders = bundles.filter_map do |klass, max_fields|
      count = klass.members.length
      "#{klass.name} (#{count} > #{max_fields})" if count > max_fields
    end

    failure_message = "Reader runtime bundle field budget exceeded:\n#{offenders.join("\n")}"
    expect(offenders).to be_empty, failure_message
  end
end
