# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Persists reading progress as the user navigates, so a crash, a
          # killed terminal, or a dropped SSH session loses at most a couple of
          # seconds of position instead of the whole session (progress was
          # previously written only on a clean quit).
          #
          # Chapter changes save immediately — they are infrequent and the most
          # costly position to lose. Page turns are throttled so holding a
          # navigation key does not hammer the progress file.
          class ProgressAutosave
            MIN_SAVE_INTERVAL_SECONDS = 2.0

            def initialize(controller:, clock:, min_interval: MIN_SAVE_INTERVAL_SECONDS)
              @controller = controller
              @clock = clock
              @min_interval = min_interval
              @last_save_at = nil
            end

            def note_chapter_change
              save!
            end

            def note_position_change
              return if throttled?

              save!
            end

            private

            def throttled?
              @last_save_at && (monotonic_now - @last_save_at) < @min_interval
            end

            def save!
              @controller.save_progress
              @last_save_at = monotonic_now
            end

            def monotonic_now
              @clock.monotonic_now
            end
          end
        end
      end
    end
  end
end
