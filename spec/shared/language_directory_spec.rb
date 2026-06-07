# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::LanguageDirectory do
  describe '.name_for' do
    it 'resolves known codes to friendly names' do
      expect(described_class.name_for('de')).to eq('German')
    end

    it 'labels the auto code as detect language' do
      expect(described_class.name_for('auto')).to eq('Detect language')
    end

    it 'falls back to the upcased code for unknown languages' do
      expect(described_class.name_for('xx')).to eq('XX')
    end
  end

  describe '.fallback_languages' do
    it 'leads with the preferred languages and includes a broad set' do
      langs = described_class.fallback_languages

      expect(langs.first[:code]).to eq('en')
      expect(langs.map { |l| l[:code] }).to include('de', 'fr', 'ja')
      expect(langs).to all(include(:code, :name))
    end
  end

  describe '.candidates_for' do
    let(:languages) { [{ code: 'en', name: 'English' }, { code: 'de', name: 'German' }] }

    it 'prepends the auto entry for the source side only' do
      source = described_class.candidates_for(languages, side: :source, query: '')
      target = described_class.candidates_for(languages, side: :target, query: '')

      expect(source.first[:code]).to eq('auto')
      expect(target.map { |l| l[:code] }).not_to include('auto')
    end

    it 'filters by code or name, case-insensitively' do
      by_name = described_class.candidates_for(languages, side: :target, query: 'ger')
      by_code = described_class.candidates_for(languages, side: :target, query: 'EN')

      expect(by_name.map { |l| l[:code] }).to eq(['de'])
      expect(by_code.map { |l| l[:code] }).to eq(['en'])
    end

    it 'normalizes backend language objects that respond to code/name' do
      backend = Shoko::Core::Models::TranslationLanguage.new(code: 'fr', name: 'French')
      result = described_class.candidates_for([backend], side: :target, query: '')

      expect(result).to eq([{ code: 'fr', name: 'French' }])
    end
  end
end
