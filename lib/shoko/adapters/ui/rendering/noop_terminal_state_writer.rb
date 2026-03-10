# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Rendering
        # Menu rendering should not persist terminal size into reader session state.
        class NoopTerminalStateWriter
          def update_terminal_size(_width, _height); end
        end
      end
    end
  end
end
