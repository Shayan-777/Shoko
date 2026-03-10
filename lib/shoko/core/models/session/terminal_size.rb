# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        TerminalSizeFields = %i[width height].freeze

        # Immutable terminal dimensions snapshot.
        class TerminalSize < Data.define(*TerminalSizeFields)
          def self.build(width:, height:)
            new(width: width.to_i, height: height.to_i)
          end
        end
      end
    end
  end
end
