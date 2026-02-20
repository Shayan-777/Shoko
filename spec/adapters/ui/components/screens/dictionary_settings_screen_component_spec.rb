# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Presentation::Ui::Components::Screens::DictionarySettingsScreenComponent do
  let(:config_reader) { instance_double('ConfigReader') }
  let(:dictionary_availability) { instance_double('DictionaryAvailability', sqlite3_available?: true) }
  let(:dictionary_storage) do
    instance_double(
      'DictionaryStorage',
      databases_present?: false,
      default_databases_path: '/tmp/shoko/dictionary',
      display_path: '/tmp/shoko/dictionary'
    )
  end
  let(:runtime_config) { instance_double('RuntimeConfig', dictionary_backend_override: nil) }
  let(:dependencies) { instance_double('Dependencies') }
  subject(:component) { described_class.new(dependencies: dependencies) }

  before do
    allow(dependencies).to receive(:config_reader).and_return(config_reader)
    allow(dependencies).to receive(:menu_state_reader).and_return(nil)
    allow(dependencies).to receive(:dictionary_availability).and_return(dictionary_availability)
    allow(dependencies).to receive(:dictionary_storage).and_return(dictionary_storage)
    allow(dependencies).to receive(:runtime_config).and_return(runtime_config)
  end

  describe '#lookup_value' do
    before do
      allow(config_reader).to receive(:dictionary_path).and_return(nil)
    end

    it 'shows enabled when backend is sqlite and sqlite3 is available' do
      allow(config_reader).to receive(:dictionary_backend).and_return(:sqlite)
      allow(dictionary_availability).to receive(:sqlite3_available?).and_return(true)

      expect(component.send(:lookup_value)).to eq('Enabled')
    end

    it 'shows needs sqlite3 when backend is sqlite but gem is missing' do
      allow(config_reader).to receive(:dictionary_backend).and_return(:sqlite)
      allow(dictionary_availability).to receive(:sqlite3_available?).and_return(false)

      expect(component.send(:lookup_value)).to eq('Needs sqlite3')
    end

    it 'shows disabled when backend is nil' do
      allow(config_reader).to receive(:dictionary_backend).and_return(nil)
      allow(dictionary_availability).to receive(:sqlite3_available?).and_return(true)

      expect(component.send(:lookup_value)).to eq('Enabled (no datasets)')
    end

    it 'shows enabled when backend is auto and databases are present' do
      allow(config_reader).to receive(:dictionary_backend).and_return(nil)
      allow(config_reader).to receive(:dictionary_path).and_return(nil)
      allow(dictionary_availability).to receive(:sqlite3_available?).and_return(true)
      allow(dictionary_storage).to receive(:databases_present?).and_return(true)

      expect(component.send(:lookup_value)).to eq('Enabled')
    end
  end
end
