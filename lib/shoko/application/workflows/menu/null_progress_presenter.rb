# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Menu
        # No-op progress presenter used when the overlay is skipped.
        class NullProgressPresenter
          def show(*) end

          def update(*) end

          def update_status(*) end

          def update_message(*) end

          def update_progress(*) end

          def clear(*) end
        end
      end
    end
  end
end
