# frozen_string_literal: true

module Shoko
  module Core
    module Errors
      # Typed dictionary boundary failure used across core/application/adapters.
      class DictionaryFailure < StandardError
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
