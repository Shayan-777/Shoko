# frozen_string_literal: true

require_relative '../../shared/errors'

module Shoko
  module Core
    module Errors
      # Typed failure shared by translation ports and the core service.
      class TranslationFailure < Shoko::Error
        attr_reader :code

        def initialize(message, code: :unknown)
          super(message)
          @code = code.to_sym
        end
      end
    end
  end
end
