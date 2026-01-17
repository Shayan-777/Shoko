# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::SettingsService do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  let(:state_store) { Shoko::Application::Infrastructure::StateStore.new }
  let(:dependencies) do
    FakeContainer.new(state_store: state_store, terminal_service: instance_double('TerminalService'))
  end

  subject(:service) { described_class.new(dependencies) }

  describe '#toggle_dictionary_backend' do
    it 'toggles dictionary backend between nil and :sqlite' do
      expect(state_store.get(%i[config dictionary_backend])).to be_nil

      service.toggle_dictionary_backend
      expect(state_store.get(%i[config dictionary_backend])).to eq(:sqlite)

      service.toggle_dictionary_backend
      expect(state_store.get(%i[config dictionary_backend])).to be_nil
    end
  end
end
