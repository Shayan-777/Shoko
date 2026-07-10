# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::TranslationService do
  let(:repository) { instance_double(Shoko::Application::Ports::Outbound::TranslationRepository) }

  subject(:service) { described_class.new(translation_repository: repository, logger: Shoko::Core::Services::NullLogger.new) }

  it 'returns backend languages when available' do
    languages = [
      Shoko::Core::Models::TranslationLanguage.new(code: 'de', name: 'German'),
      Shoko::Core::Models::TranslationLanguage.new(code: 'en', name: 'English')
    ]
    allow(repository).to receive(:available_languages).and_return(languages)

    expect(service.available_languages).to eq(languages)
  end

  it 'returns an empty language list when the repository is unavailable' do
    unavailable = described_class.new(translation_repository: nil)

    expect(unavailable.available_languages).to eq([])
  end

  it 'returns an empty success result for blank input' do
    result = service.translate('   ')

    expect(result).to be_success
    expect(result.query).to eq('')
    expect(result.translated_text).to eq('')
    expect(result.source_lang).to eq('auto')
    expect(result.target_lang).to eq('en')
  end

  it 'delegates translation with normalized defaults' do
    result = Shoko::Core::Models::TranslationResult.new(
      query: 'Hallo',
      translated_text: 'Hello',
      source_lang: 'auto',
      target_lang: 'en',
      detected_source_lang: 'de'
    )
    allow(repository).to receive(:translate).and_return(result)

    translated = service.translate('Hallo', source_lang: '', target_lang: '')

    expect(repository).to have_received(:translate).with('Hallo', source_lang: 'auto', target_lang: 'en')
    expect(translated.translated_text).to eq('Hello')
    expect(translated.detected_source_lang).to eq('de')
  end

  it 'wraps repository failures into an error result' do
    allow(repository).to receive(:translate).and_raise(
      Shoko::Application::Ports::Outbound::TranslationRepository::RepositoryError.new('backend down', code: :connection_failed)
    )

    result = service.translate('Hallo', source_lang: 'auto', target_lang: 'en')

    expect(result).to be_error
    expect(result.error_message).to eq('backend down')
    expect(result.translated_text).to eq('')
  end
end
