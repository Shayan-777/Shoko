# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for warming a freshly imported document so it opens
        # immediately in the subsequent session (e.g. persisted pagination).
        module DocumentWarmup
          # @param document [Object] Loaded document to warm
          # @param progress_reporter [Object, nil] Progress reporter with #update_status
          # @return [Symbol] :warmed, :skipped, or :error
          def warm(document, progress_reporter: nil)
            raise NotImplementedError, "#{self.class} must implement #warm"
          end
        end
      end
    end
  end
end
