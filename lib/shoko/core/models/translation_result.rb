# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Language metadata returned by the translation backend.
      TranslationLanguage = Data.define(:code, :name, :targets) do
        def initialize(code:, name:, targets: [])
          super(code: code.to_s.freeze, name: name.to_s.freeze, targets: Array(targets).map(&:to_s).freeze)
        end

        def to_h
          {
            code: code,
            name: name,
            targets: targets,
          }
        end
      end

      # Result container for translation requests.
      TranslationResult = Data.define(
        :query,
        :translated_text,
        :source_lang,
        :target_lang,
        :detected_source_lang,
        :error_message
      ) do
        def initialize(query:, translated_text:, source_lang:, target_lang:,
                       detected_source_lang: nil, error_message: nil)
          super(
            query: query.to_s.freeze,
            translated_text: translated_text.to_s.freeze,
            source_lang: source_lang.to_s.freeze,
            target_lang: target_lang.to_s.freeze,
            detected_source_lang: detected_source_lang&.to_s&.freeze,
            error_message: error_message&.to_s&.freeze
          )
        end

        def success?
          error_message.to_s.empty?
        end

        def error?
          !success?
        end
      end
    end
  end
end
