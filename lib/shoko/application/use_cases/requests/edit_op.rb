# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Requests
        VALID_EDIT_OPS = %i[insert backspace delete newline].freeze

        # Immutable single text-input edit operation. The operation kind is required;
        # text is required for :insert and forbidden for the other ops.
        EditOp = Data.define(:operation, :text) do
          def initialize(operation:, text: nil)
            unless VALID_EDIT_OPS.include?(operation)
              raise ArgumentError, "operation must be one of #{VALID_EDIT_OPS.join(', ')}"
            end
            raise ArgumentError, ':insert requires non-empty text' if operation == :insert && text.to_s.empty?
            raise ArgumentError, 'text is only valid with :insert' if !text.to_s.empty? && operation != :insert

            super
          end
        end
      end
    end
  end
end
