# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Narrow writer for library pre-pagination progress, surfaced as the menu
        # toast. Implementations MUST update only the prepagination fields so a
        # write from the warmup worker thread never clobbers concurrent menu-state
        # edits made on the main thread.
        module PrepaginationProgressWriter
          # Begin a batch of +total+ books processed in +paths+ order (shows the
          # toast, resets the counter, and publishes the per-book queue so the
          # library can mark each book ready/recalculating/queued).
          def start(total:, paths:)
            raise NotImplementedError, "#{self.class} must implement #start"
          end

          # Record that +done+ books have been paginated so far.
          def report(done:)
            raise NotImplementedError, "#{self.class} must implement #report"
          end

          # End the batch (hide the toast, reset the counter).
          def finish
            raise NotImplementedError, "#{self.class} must implement #finish"
          end
        end
      end
    end
  end
end
