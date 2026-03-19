# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Requests
        # Immutable mode transition request emitted by input adapters.
        ModeChange = Data.define(:mode) do
          def initialize(mode:)
            raise ArgumentError, 'mode must be a Symbol' unless mode.is_a?(Symbol)

            super
          end
        end
      end
    end
  end
end
