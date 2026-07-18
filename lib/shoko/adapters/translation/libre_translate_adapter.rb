# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative '../base_adapter'
require_relative '../../core/models/translation_language'
require_relative '../../core/models/translation_result'
require_relative '../../application/ports/outbound/translation_repository'

module Shoko
  module Adapters
    module Translation
      # HTTP adapter for a self-hosted LibreTranslate instance.
      class LibreTranslateAdapter < Shoko::Adapters::BaseAdapter
        include Shoko::Application::Ports::Outbound::TranslationRepository

        DEFAULT_BASE_URL = 'http://127.0.0.1:5000'
        OPEN_TIMEOUT = 3
        READ_TIMEOUT = 10
        MAX_RESPONSE_BODY_BYTES = 8 * 1024 * 1024

        def initialize(base_url: DEFAULT_BASE_URL, logger: nil)
          super(logger: logger)
          @base_uri = normalized_base_uri(base_url)
        end

        def available_languages
          response = get_json('/languages')
          Array(response).map { |item| build_language(item) }.sort_by { |language| language.name.downcase }
        rescue JSON::ParserError => e
          raise RepositoryError.new("Invalid languages response: #{e.message}", code: :invalid_response)
        end

        def translate(text, source_lang:, target_lang:)
          payload = {
            q: text.to_s,
            source: source_lang.to_s,
            target: target_lang.to_s,
            format: 'text',
          }
          response = post_json('/translate', payload)
          build_translation_result(text, source_lang: source_lang, target_lang: target_lang, response: response)
        rescue JSON::ParserError => e
          raise RepositoryError.new("Invalid translation response: #{e.message}", code: :invalid_response)
        end

        private

        def normalized_base_uri(base_url)
          uri = URI.parse(base_url.to_s)
          unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
            raise ArgumentError, "Invalid LibreTranslate base URL: #{base_url.inspect}"
          end

          uri
        rescue URI::InvalidURIError => e
          raise ArgumentError, "Invalid LibreTranslate base URL: #{e.message}"
        end

        def build_language(item)
          normalized = normalize_hash(item)
          Shoko::Core::Models::TranslationLanguage.new(
            code: normalized.fetch(:code),
            name: normalized.fetch(:name),
            targets: normalized[:targets] || []
          )
        rescue KeyError => e
          raise RepositoryError.new("Incomplete language entry: #{e.message}", code: :invalid_response)
        end

        def build_translation_result(text, source_lang:, target_lang:, response:)
          normalized = normalize_hash(response)
          translated_text = normalized[:translated_text]
          raise RepositoryError.new('Missing translated text', code: :invalid_response) if translated_text.nil?

          detected = normalize_hash(normalized[:detected_language] || {})
          Shoko::Core::Models::TranslationResult.new(
            query: text,
            translated_text: translated_text,
            source_lang: source_lang,
            target_lang: target_lang,
            detected_source_lang: detected[:language]
          )
        end

        def get_json(path)
          request_json(Net::HTTP::Get.new(build_uri(path)))
        end

        def post_json(path, payload)
          request = Net::HTTP::Post.new(build_uri(path))
          request['Content-Type'] = 'application/json'
          request.body = JSON.generate(payload)
          request_json(request)
        end

        # Block-form request so bodies (success AND error — both are
        # consumed) are read in bounded chunks instead of buffered whole.
        def request_json(request)
          response = with_http(request.uri) do |http|
            http.request(request) { |partial| partial.body = read_bounded_body(partial) }
          end
          raise_for_http_error(response) unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body, symbolize_names: true)
        rescue IOError, SystemCallError, SocketError, Timeout::Error => e
          raise RepositoryError.new("LibreTranslate request failed: #{e.message}", code: :connection_failed)
        end

        def read_bounded_body(response)
          buffer = +''
          response.read_body do |chunk|
            if buffer.bytesize + chunk.bytesize > MAX_RESPONSE_BODY_BYTES
              raise RepositoryError.new("LibreTranslate response exceeded #{MAX_RESPONSE_BODY_BYTES} bytes",
                                        code: :response_too_large)
            end

            buffer << chunk
          end
          buffer
        end

        def raise_for_http_error(response)
          body = response.body.to_s.strip
          message = body.empty? ? "LibreTranslate request failed (#{response.code})" : body
          raise RepositoryError.new(message, code: :http_error)
        end

        def with_http(uri, &)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          http.start(&)
        end

        def build_uri(path)
          URI.join(base_uri_string, path)
        end

        def base_uri_string
          raw = @base_uri.to_s
          raw.end_with?('/') ? raw : "#{raw}/"
        end

        def normalize_hash(value)
          return {} unless value.is_a?(Hash)

          value.transform_keys do |key|
            key.to_s.gsub(/([A-Z])/, '_\1').downcase.to_sym
          end
        end
      end
    end
  end
end
