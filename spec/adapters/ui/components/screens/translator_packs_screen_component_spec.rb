# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::TranslatorPacksScreenComponent do
  let(:config_reader) { instance_double(Shoko::Application::Ports::Outbound::State::ConfigSnapshot) }
  let(:dependencies) { instance_double(Shoko::Adapters::Ui::MenuUiDependencies, menu_hit_registry: nil) }
  let(:menu_state_reader) do
    instance_double(
      Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter,
      translator_packs_results: packs_results,
      translator_packs_selected: 0,
      translator_packs_query: '',
      translator_packs_cursor: 0,
      mode: :translator_packs,
      translator_packs_status: :done,
      translator_packs_message: '',
      translator_packs_progress: 0.0,
      translation_engine_available: engine_available,
      translation_engine_build_hint: 'make -C ext/shoko_translate'
    )
  end
  let(:packs_results) do
    [
      { from: 'et', to: 'en', version: '1.0', size: 17_000_000, installed: true },
      { from: 'en', to: 'de', version: '2.1', size: 32_000_000, installed: false },
    ]
  end

  subject(:component) { described_class.new(menu_state_reader: menu_state_reader, config_reader: config_reader) }

  let(:engine_available) { false }

  before do
    allow(config_reader).to receive(:translator_backend).and_return(:local)
    allow(dependencies).to receive_messages(config_reader: config_reader, menu_state_reader: menu_state_reader)
  end

  describe '#backend_value' do
    it 'names the on-device backend' do
      expect(component.send(:backend_value)).to eq('On-device (local)')
    end

    it 'names the LibreTranslate backend when selected' do
      allow(config_reader).to receive(:translator_backend).and_return(:libretranslate)
      expect(component.send(:backend_value)).to eq('LibreTranslate server')
    end
  end

  describe '#engine_value' do
    context 'when the engine binary is available' do
      let(:engine_available) { true }

      it 'shows ready' do
        expect(component.send(:engine_value)).to eq('Ready')
      end
    end

    it 'shows the build hint when the engine is missing' do
      expect(component.send(:engine_value)).to include('make -C ext/shoko_translate')
    end
  end

  describe 'pack rows' do
    it 'formats pairs with language names' do
      expect(component.send(:format_pair, packs_results.first)).to eq('Estonian → English')
    end

    it 'formats sizes in megabytes' do
      expect(component.send(:format_size, 17_000_000)).to eq('16 MB')
    end

    it 'filters packs by code or language name' do
      allow(menu_state_reader).to receive(:translator_packs_query).and_return('german')
      expect(component.send(:filtered_results).length).to eq(1)
      allow(menu_state_reader).to receive(:translator_packs_query).and_return('et-en')
      expect(component.send(:filtered_results).length).to eq(1)
    end

    it 'shows both installed and available versions for an update' do
      item = packs_results.last.merge(
        installed: true,
        installed_version: '1.9',
        update_available: true
      )

      expect(component.send(:pack_version_and_size, item)).to include('v1.9 → v2.1')
    end
  end

  describe '#status_label' do
    it 'summarizes the filtered pack count when idle' do
      expect(component.send(:status_label)).to eq('2 language packs')
    end

    it 'passes error messages through' do
      allow(menu_state_reader).to receive_messages(
        translator_packs_status: :error, translator_packs_message: 'Catalog failed: offline'
      )
      expect(component.send(:status_label)).to eq('Catalog failed: offline')
    end
  end
end
