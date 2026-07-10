# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::DictionarySettingsScreenComponent do
  class RecordingOutput
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(row, col, text)
      @writes << { row: row, col: col, text: text }
    end
  end

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
  let(:dependencies) { instance_double('Dependencies', menu_hit_registry: nil) }
  let(:menu_state_reader) do
    instance_double(
      'MenuStateReader',
      dictionary_results: [],
      dictionary_selected: 0,
      dictionary_query: '',
      dictionary_cursor: 0,
      mode: :dictionary,
      dictionary_status: :loading,
      dictionary_message: '',
      dictionary_progress: 0.0
    )
  end
  subject(:component) { described_class.new(dependencies: dependencies) }

  before do
    allow(config_reader).to receive_messages(
      dictionary_backend: nil,
      dictionary_source_lang: nil,
      dictionary_target_lang: 'en',
      dictionary_path: nil
    )
    allow(dependencies).to receive(:config_reader).and_return(config_reader)
    allow(dependencies).to receive(:menu_state_reader).and_return(menu_state_reader)
    allow(dependencies).to receive(:dictionary_availability).and_return(dictionary_availability)
    allow(dependencies).to receive(:dictionary_storage).and_return(dictionary_storage)
    allow(dependencies).to receive(:runtime_config).and_return(runtime_config)
  end

  describe '#lookup_value' do
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

  describe '#render' do
    it 'renders the loading empty state without raising' do
      output = RecordingOutput.new
      surface = Shoko::Adapters::Ui::Components::Surface.new(output)
      bounds = Shoko::Adapters::Ui::Components::Rect.new(1, 1, 80, 24)

      expect { component.render(surface, bounds) }.not_to raise_error
      expect(output.writes.any? { |entry| entry[:text].include?('Loading dictionary list…') }).to be(true)
    end
  end
end
