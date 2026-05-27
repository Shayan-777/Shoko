# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Immutable terminal dimensions value object exchanged across the
          # reader runtime-context port boundary.
          TerminalSize = Data.define(:width, :height) do
            def self.build(width:, height:)
              new(width: width.to_i, height: height.to_i)
            end
          end
        end
      end
    end
  end
end
