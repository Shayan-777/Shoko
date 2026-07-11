# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Redraws the menu from adapter-side state observation for workflow-driven progress updates.
          class WorkflowRenderObserver
            THROTTLE_INTERVAL = 0.05

            FORCED_PATHS = [
              %i[menu loading_active],
              %i[menu loading_path],
              %i[menu loading_index],
              %i[menu loading_mode],
              %i[menu download_status],
              %i[menu download_results],
              %i[menu download_count],
              %i[menu download_next],
              %i[menu download_prev],
              %i[menu download_selected],
              %i[menu dictionary_status],
              %i[menu dictionary_results],
              %i[menu dictionary_selected],
              %i[menu translator_packs_status],
              %i[menu translator_packs_results],
              %i[menu translator_packs_selected],
            ].freeze

            THROTTLED_PATHS = [
              %i[menu loading_message],
              %i[menu loading_progress],
              %i[menu download_message],
              %i[menu download_progress],
              %i[menu dictionary_message],
              %i[menu dictionary_progress],
              %i[menu translator_packs_message],
              %i[menu translator_packs_progress],
            ].freeze

            OBSERVED_PATHS = (FORCED_PATHS + THROTTLED_PATHS).freeze

            def initialize(menu:, clock:, logger: nil)
              @menu = menu
              @clock = clock
              @logger = logger
              @last_draw_at = nil
            end

            def observed_paths
              OBSERVED_PATHS
            end

            def state_changed(path, _old_value, new_value)
              return unless OBSERVED_PATHS.include?(path)
              return if loading_teardown?(path, new_value)

              force = FORCED_PATHS.include?(path) || completed_progress?(path, new_value)
              request_draw(force: force)
            rescue Shoko::Error => e
              @logger&.debug('menu.workflow_render_observer.state_changed_failed',
                             path: path,
                             error: e.class.name,
                             message: e.message)
            end

            private

            # Clearing the loading overlay must not repaint the menu: a book
            # launch keeps the 100% frame on screen until the reader's first
            # paint replaces it, and once control returns to the menu loop it
            # repaints on its own. Painting here flashed the browse screen
            # between "100%" and the reader.
            def loading_teardown?(path, new_value)
              return false unless path[1].to_s.start_with?('loading_')
              return new_value != true if path == %i[menu loading_active]

              new_value.nil?
            end

            # A bar reaching 100% is the frame the user reads as "done" — it
            # must paint immediately, never fall into the throttle window.
            def completed_progress?(path, new_value)
              THROTTLED_PATHS.include?(path) &&
                path[1].to_s.end_with?('_progress') &&
                new_value.to_f >= 1.0
            end

            def request_draw(force:)
              now = monotonic_now
              return if !force && throttled?(now)

              @menu.draw_screen
              @last_draw_at = now
            end

            def throttled?(now)
              @last_draw_at && (now - @last_draw_at) < THROTTLE_INTERVAL
            end

            def monotonic_now
              return 0.0 unless @clock

              @clock.monotonic_now
            end
          end
        end
      end
    end
  end
end
