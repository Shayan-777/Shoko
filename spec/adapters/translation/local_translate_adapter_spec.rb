# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Translation::LocalTranslateAdapter do
  RepositoryError = Shoko::Application::Ports::Outbound::TranslationRepository::RepositoryError

  def pack(from, to)
    Shoko::Adapters::Translation::ModelStore::InstalledPack.new(
      from: from, to: to, dir: "/packs/#{from}-#{to}",
      model_path: "/packs/#{from}-#{to}/model.bin",
      vocab_path: "/packs/#{from}-#{to}/vocab.spm",
      version: '1.0'
    )
  end

  let(:engine_client) { instance_double(Shoko::Adapters::Translation::EngineClient) }
  let(:model_store) { instance_double(Shoko::Adapters::Translation::ModelStore) }

  subject(:adapter) { described_class.new(engine_client: engine_client, model_store: model_store) }

  def stub_packs(*packs)
    allow(model_store).to receive(:installed_packs).and_return(packs)
    allow(model_store).to receive(:find) do |from, to|
      packs.find { |p| p.from == from && p.to == to }
    end
    allow(model_store).to receive(:installed?) do |from, to|
      packs.any? { |p| p.from == from && p.to == to }
    end
  end

  def stub_engine_echo(prefix)
    allow(engine_client).to receive(:ensure_loaded)
    allow(engine_client).to receive(:translate) { |slot, text| "#{prefix}[#{slot}:#{text}]" }
  end

  describe '#available_languages' do
    it 'is empty with no packs installed' do
      stub_packs
      expect(adapter.available_languages).to eq([])
    end

    it 'lists installed languages with pivot-extended targets' do
      stub_packs(pack('et', 'en'), pack('en', 'de'))
      languages = adapter.available_languages
      estonian = languages.find { |l| l.code == 'et' }
      expect(estonian.targets).to contain_exactly('de', 'en')
      expect(languages.map(&:code)).to contain_exactly('et', 'en', 'de')
    end
  end

  describe '#translate' do
    it 'translates through a direct pack' do
      stub_packs(pack('et', 'en'))
      stub_engine_echo('X')
      result = adapter.translate('Tere!', source_lang: 'et', target_lang: 'en')
      expect(result.translated_text).to eq('X[et-en:Tere!]')
      expect(result.error?).to be(false)
    end

    it 'pivots through English when no direct pack exists' do
      stub_packs(pack('et', 'en'), pack('en', 'de'))
      stub_engine_echo('X')
      result = adapter.translate('Tere!', source_lang: 'et', target_lang: 'de')
      expect(result.translated_text).to eq('X[en-de:X[et-en:Tere!]]')
    end

    it 'translates sentence by sentence and preserves paragraph breaks' do
      stub_packs(pack('et', 'en'))
      stub_engine_echo('X')
      result = adapter.translate("Üks. Kaks.\n\nKolm.", source_lang: 'et', target_lang: 'en')
      expect(result.translated_text).to eq("X[et-en:Üks.] X[et-en:Kaks.]\nX[et-en:Kolm.]")
    end

    it 'resolves auto source when exactly one installed pack reaches the target' do
      stub_packs(pack('et', 'en'))
      stub_engine_echo('X')
      result = adapter.translate('Tere!', source_lang: 'auto', target_lang: 'en')
      expect(result.detected_source_lang).to eq('et')
    end

    it 'rejects auto source when the route is ambiguous' do
      stub_packs(pack('et', 'en'), pack('de', 'en'))
      expect { adapter.translate('Tere!', source_lang: 'auto', target_lang: 'en') }
        .to raise_error(RepositoryError) { |e| expect(e.code).to eq(:source_required) }
    end

    it 'raises model_missing for an uninstalled pair' do
      stub_packs(pack('et', 'en'))
      expect { adapter.translate('hi', source_lang: 'en', target_lang: 'fr') }
        .to raise_error(RepositoryError) { |e| expect(e.code).to eq(:model_missing) }
    end

    it 'rejects same source and target' do
      stub_packs(pack('et', 'en'))
      expect { adapter.translate('hi', source_lang: 'en', target_lang: 'en') }
        .to raise_error(RepositoryError) { |e| expect(e.code).to eq(:invalid_request) }
    end

    it 'translates engine failures into repository errors' do
      stub_packs(pack('et', 'en'))
      allow(engine_client).to receive(:ensure_loaded)
      allow(engine_client).to receive(:translate)
        .and_raise(Shoko::Adapters::Translation::EngineClient::EngineError.new('boom', code: :engine_failed))
      expect { adapter.translate('Tere!', source_lang: 'et', target_lang: 'en') }
        .to raise_error(RepositoryError) { |e| expect(e.code).to eq(:engine_failed) }
    end

    it 'retries a segment once after an engine crash' do
      stub_packs(pack('et', 'en'))
      allow(engine_client).to receive(:ensure_loaded)
      calls = 0
      allow(engine_client).to receive(:translate) do |_slot, text|
        calls += 1
        raise Shoko::Adapters::Translation::EngineClient::EngineError.new('died', code: :engine_died) if calls == 1

        "OK[#{text}]"
      end
      result = adapter.translate('Tere!', source_lang: 'et', target_lang: 'en')
      expect(result.translated_text).to eq('OK[Tere!]')
    end
  end
end
