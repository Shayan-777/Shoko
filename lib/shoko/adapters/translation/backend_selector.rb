# frozen_string_literal: true

require_relative '../../application/ports/outbound/translation_repository'

module Shoko
  module Adapters
    module Translation
      # Routes translation calls to the backend the user selected in settings
      # (config field :translator_backend). Backends are built lazily from
      # injected factories so an unused backend costs nothing; switching in
      # the settings screen takes effect on the next call, no restart needed.
      class BackendSelector
        include Shoko::Application::Ports::Outbound::TranslationRepository

        DEFAULT_BACKEND = :local
        KNOWN_BACKENDS = %i[local libretranslate].freeze

        def initialize(backend_factories:, config_reader:, logger: nil)
          @factories = backend_factories
          @config_reader = config_reader
          @logger = logger
          @backends = {}
        end

        def available_languages
          current_backend.available_languages
        end

        def translate(text, source_lang:, target_lang:)
          current_backend.translate(text, source_lang: source_lang, target_lang: target_lang)
        end

        def current_backend_key
          raw = @config_reader.translator_backend
          key = raw.to_s.to_sym
          KNOWN_BACKENDS.include?(key) ? key : DEFAULT_BACKEND
        end

        private

        def current_backend
          key = current_backend_key
          @backends[key] ||= @factories.fetch(key).call
        end
      end
    end
  end
end
