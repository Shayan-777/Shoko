# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Requests
        # Immutable typed input for printable text entry.
        class TextInput < Data.define(:text)
          def initialize(text:)
            unless text.is_a?(String) && !text.empty?
              raise ArgumentError, 'text must be a non-empty String'
            end

            super(text: text)
          end
        end
      end
    end
  end
end
