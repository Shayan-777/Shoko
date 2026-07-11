# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Translation::BackendSelector do
  let(:backend_setting) { :local }
  let(:local_backend) { instance_double(Shoko::Adapters::Translation::LocalTranslateAdapter) }
  let(:libre_backend) { instance_double(Shoko::Adapters::Translation::LibreTranslateAdapter) }
  let(:config_reader) do
    instance_double(Shoko::Application::Ports::Outbound::State::ConfigSnapshot, translator_backend: backend_setting)
  end
  let(:local_builds) { [] }

  subject(:selector) do
    described_class.new(
      backend_factories: {
        local: -> { local_builds << :built; local_backend },
        libretranslate: -> { libre_backend },
      },
      config_reader: config_reader
    )
  end

  context 'with the default (local) backend' do
    let(:backend_setting) { :local }

    it 'routes translate to the local adapter' do
      expect(local_backend).to receive(:translate)
        .with('hi', source_lang: 'et', target_lang: 'en')
      selector.translate('hi', source_lang: 'et', target_lang: 'en')
    end

    it 'routes available_languages to the local adapter and builds it once' do
      allow(local_backend).to receive(:available_languages).and_return([])
      selector.available_languages
      selector.available_languages
      expect(local_builds.length).to eq(1)
    end
  end

  context 'with libretranslate selected' do
    let(:backend_setting) { :libretranslate }

    it 'routes to the LibreTranslate adapter without touching the local factory' do
      allow(libre_backend).to receive(:available_languages).and_return([])
      selector.available_languages
      expect(local_builds).to be_empty
    end
  end

  context 'with an unknown backend value' do
    let(:backend_setting) { 'garbage' }

    it 'falls back to the local backend' do
      expect(selector.current_backend_key).to eq(:local)
    end
  end

  it 'switches backends when the config changes between calls' do
    allow(config_reader).to receive(:translator_backend).and_return(:local, :libretranslate)
    allow(local_backend).to receive(:available_languages).and_return([])
    allow(libre_backend).to receive(:available_languages).and_return([])
    selector.available_languages
    selector.available_languages
    expect(local_backend).to have_received(:available_languages).once
    expect(libre_backend).to have_received(:available_languages).once
  end
end
