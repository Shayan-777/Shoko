# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::Screens::DictionarySettingsScreenComponent do
  let(:state) { instance_double('State') }
  subject(:component) { described_class.new(state) }

  describe '#lookup_value' do
    before do
      allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:databases_present?).and_return(false)
      allow(state).to receive(:get).with(%i[config dictionary_path]).and_return(nil)
    end

    it 'shows enabled when backend is sqlite and sqlite3 is available' do
      allow(state).to receive(:get).with(%i[config dictionary_backend]).and_return(:sqlite)
      allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)

      expect(component.send(:lookup_value)).to eq('Enabled')
    end

    it 'shows needs sqlite3 when backend is sqlite but gem is missing' do
      allow(state).to receive(:get).with(%i[config dictionary_backend]).and_return(:sqlite)
      allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(false)

      expect(component.send(:lookup_value)).to eq('Needs sqlite3')
    end

    it 'shows disabled when backend is nil' do
      allow(state).to receive(:get).with(%i[config dictionary_backend]).and_return(nil)
      allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)

      expect(component.send(:lookup_value)).to eq('Disabled')
    end

    it 'shows enabled when backend is auto and databases are present' do
      allow(state).to receive(:get).with(%i[config dictionary_backend]).and_return(nil)
      allow(state).to receive(:get).with(%i[config dictionary_path]).and_return(nil)
      allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)
      allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:databases_present?).and_return(true)

      expect(component.send(:lookup_value)).to eq('Enabled')
    end
  end
end
