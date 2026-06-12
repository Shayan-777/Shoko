# frozen_string_literal: true

require 'shoko/shared/errors'

module Shoko
  module Application
    module Ports
      module Outbound
        # Translation backend contract used by the translation service.
        module TranslationRepository
          # Typed translation backend failure surfaced to the domain service.
          class RepositoryError < Shoko::Error
            attr_reader :code

            def initialize(message, code: :unknown)
              super(message)
              @code = code
            end
          end

          def available_languages
            raise NotImplementedError, "#{self.class} must implement #available_languages"
          end

          def translate(text, source_lang:, target_lang:)
            raise NotImplementedError, "#{self.class} must implement #translate"
          end
        end
      end
    end
  end
end
