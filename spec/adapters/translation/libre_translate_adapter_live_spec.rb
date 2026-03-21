# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Translation::LibreTranslateAdapter do
  it 'translates text against the local LibreTranslate instance' do
    skip 'set SHOKO_LIVE_TRANSLATION=1 to run live translator verification' unless ENV['SHOKO_LIVE_TRANSLATION'] == '1'

    adapter = described_class.new(base_url: 'http://127.0.0.1:5000')
    languages = adapter.available_languages
    result = adapter.translate('Hallo Welt', source_lang: 'auto', target_lang: 'en')

    expect(languages.map(&:code)).to include('en')
    expect(result.translated_text.downcase).to include('hello')
    expect(result.detected_source_lang).to eq('de')
  end
end
