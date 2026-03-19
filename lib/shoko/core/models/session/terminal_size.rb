# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        TERMINAL_SIZE_FIELDS = %i[width height].freeze

        # Immutable terminal dimensions snapshot.
        TerminalSize = Data.define(*TERMINAL_SIZE_FIELDS) do
          def self.build(width:, height:)
            new(width: width.to_i, height: height.to_i)
          end
        end
      end
    end
  end
end
