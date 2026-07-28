# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Translation::LibreTranslateAdapter do
  let(:http) { instance_double(Net::HTTP) }

  subject(:adapter) { described_class.new(base_url: 'http://127.0.0.1:5000') }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:start).and_yield(http)
  end

  def http_response(klass, code:, message:, body:)
    response = klass.new('1.1', code.to_s, message)
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, body)
    response
  end


  def non_appendable_chunk(bytesize)
    Object.new.tap do |chunk|
      chunk.define_singleton_method(:bytesize) { bytesize }
      chunk.define_singleton_method(:to_str) { raise 'oversized chunk was appended' }
    end
  end

  it 'loads and normalizes available languages' do
    allow(http).to receive(:request).and_return(
      http_response(
        Net::HTTPOK,
        code: 200,
        message: 'OK',
        body: JSON.generate(
          [
            { code: 'en', name: 'English', targets: ['de'] },
            { code: 'de', name: 'German', targets: ['en'] }
          ]
        )
      )
    )

    languages = adapter.available_languages

    expect(languages.map(&:name)).to eq(['Detect language', 'English', 'German'])
    expect(languages.first.code).to eq('auto')
    expect(languages.first.targets).to contain_exactly('de', 'en')
    expect(languages[1].targets).to eq(['de'])
  end

  it 'returns translated text with detected language metadata' do
    allow(http).to receive(:request).and_return(
      http_response(
        Net::HTTPOK,
        code: 200,
        message: 'OK',
        body: JSON.generate(
          translatedText: 'Hello world',
          detectedLanguage: { language: 'de', confidence: 0.92 }
        )
      )
    )

    result = adapter.translate('Hallo Welt', source_lang: 'auto', target_lang: 'en')

    expect(result.translated_text).to eq('Hello world')
    expect(result.detected_source_lang).to eq('de')
    expect(result.target_lang).to eq('en')
  end

  it 'raises a repository error for HTTP failures' do
    allow(http).to receive(:request).and_return(
      http_response(Net::HTTPBadRequest, code: 400, message: 'Bad Request', body: 'bad target')
    )

    expect do
      adapter.translate('Hallo', source_lang: 'auto', target_lang: '??')
    end.to raise_error(
      Shoko::Application::Ports::Outbound::TranslationRepository::RepositoryError,
      /bad target/
    )
  end

  it 'raises a repository error for network failures' do
    allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED, 'Connection refused')

    expect do
      adapter.available_languages
    end.to raise_error(
      Shoko::Application::Ports::Outbound::TranslationRepository::RepositoryError,
      /LibreTranslate request failed/
    )
  end

  it 'aborts oversized responses at the byte ceiling instead of buffering them' do
    stub_const("#{described_class}::MAX_RESPONSE_BODY_BYTES", 64)
    streaming = Net::HTTPOK.new('1.1', '200', 'OK')
    streaming.define_singleton_method(:read_body) do |&block|
      2.times { block.call('x' * 48) }
    end
    streaming.define_singleton_method(:body=) { |value| @body = value }
    allow(http).to receive(:request) do |_req, &block|
      block&.call(streaming)
      streaming
    end

    expect do
      adapter.available_languages
    end.to raise_error(
      Shoko::Application::Ports::Outbound::TranslationRepository::RepositoryError,
      /response exceeded 64 bytes/
    )
  end


  it 'checks a response chunk before appending it' do
    stub_const("#{described_class}::MAX_RESPONSE_BODY_BYTES", 64)
    chunk = non_appendable_chunk(65)
    response = Object.new
    response.define_singleton_method(:read_body) { |&block| block.call(chunk) }

    expect { adapter.send(:read_bounded_body, response) }.to raise_error(
      Shoko::Application::Ports::Outbound::TranslationRepository::RepositoryError,
      /response exceeded 64 bytes/
    )
  end
end
