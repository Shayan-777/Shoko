# frozen_string_literal: true

require_relative '../../shared/errors'

module Shoko
  module Core
    module Errors
      # Typed dictionary boundary failure used across core/application/adapters.
      # Inherits from Shoko::Error so that rescue clauses written against the
      # Shoko error family catch dictionary failures naturally — matching the
      # pattern set by `Application::Ports::Outbound::TranslationRepository::RepositoryError`.
      class DictionaryFailure < Shoko::Error
        CODES = %i[unavailable corrupt_data invalid_data permission_denied internal].freeze

        attr_reader :code, :details

        def initialize(code:, message:, details: {})
          raise ArgumentError, "Unsupported dictionary failure code: #{code.inspect}" unless CODES.include?(code)

          super(message)
          @code = code
          @details = details
        end
      end
    end
  end
end
