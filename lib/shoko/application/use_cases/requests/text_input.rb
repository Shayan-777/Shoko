# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Requests
        # Immutable typed input for printable text entry.
        TextInput = Data.define(:text) do
          def initialize(text:)
            raise ArgumentError, 'text must be a non-empty String' unless text.is_a?(String) && !text.empty?

            super
          end
        end
      end
    end
  end
end
