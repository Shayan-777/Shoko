# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::KeyDefinitions do
  it 'keeps input key definitions mapped to the shared contract' do
    expect(Shoko::Adapters::Input::KeyDefinitions::NAVIGATION).to equal(described_class::NAVIGATION)
    expect(Shoko::Adapters::Input::KeyDefinitions::ACTIONS).to equal(described_class::ACTIONS)
    expect(Shoko::Adapters::Input::KeyDefinitions::READER).to equal(described_class::READER)
    expect(Shoko::Adapters::Input::KeyDefinitions::MENU).to equal(described_class::MENU)
    expect(Shoko::Adapters::Input::KeyDefinitions::Helpers).to equal(described_class::Helpers)
  end
end
