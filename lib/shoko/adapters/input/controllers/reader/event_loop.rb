# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Encapsulates the main reader event loop.
          class EventLoop
            NOTIFICATION_POLL_INTERVAL = 0.1
            BLINK_POLL_INTERVAL = 0.1

            def initialize(controller, reader_state, metrics_start_time, instrumentation, clock:)
              @controller = controller
              @reader_state = reader_state
              @metrics_start_time = metrics_start_time
              @instrumentation = instrumentation
              raise ArgumentError, 'clock is required' if clock.nil?

              @clock = clock
              @tti_recorded = false
            end

            def run
              @controller.perform_first_paint
              startup_reference = @metrics_start_time

              initial_running = running?
              log_debug('reader.event_loop.start', running: initial_running)
              return immediate_exit unless initial_running

              run_iteration(startup_reference) while running?

              log_debug('reader.event_loop.exit', reason: 'running? became false')
            end

            private

            def run_iteration(startup_reference)
              notification_active = toast_message_active?
              blink_active = blink_redraw_active?
              keys = read_iteration_keys(notification_active, blink_active)
              record_tti(startup_reference, keys)
              resized = consume_pending_resize?
              render_requested = consume_render_request?
              applied = drain_async_results
              if !resized && !render_requested && applied.zero? &&
                 idle_iteration?(keys, notification_active, blink_active)
                return
              end

              @controller.dispatch_input_keys(keys) unless keys.empty?
              @controller.draw_screen
            end

            def blink_redraw_active?
              annotation_editor_active? || search_landing_active? ||
                translator_caret_active? || notes_caret_active? || recalculating? ||
                async_work_pending?
            end

            def running?
              @reader_state.running?
            end

            def record_tti(startup_reference, keys)
              return if @tti_recorded
              return unless startup_reference && keys.any?

              @instrumentation&.record_metric('render.tti', monotonic_now - startup_reference, 0)
              @tti_recorded = true
            end

            def toast_message_active?
              message = @reader_state.message
              message && !message.to_s.empty?
            end

            def annotation_editor_active?
              @controller.annotation_editor_active?
            end

            # Keep redrawing while the translator's source editor is focused so its
            # thin-stripe caret can blink (only in editor mode, not the language picker).
            def translator_caret_active?
              @reader_state.mode == :translator && @reader_state.translator_picker_side.nil?
            end

            # Keep redrawing while the notes compose editor is focused so its
            # thin-stripe caret can blink (only while composing, not browsing the list).
            def notes_caret_active?
              @reader_state.mode == :notes && @reader_state.notes_composing == true
            end

            # Keep redrawing while a background repagination runs so the status-bar
            # spinner animates. The heavy work is on the worker thread; this thread
            # only polls and paints. Cleared when the rebuild completes.
            def recalculating?
              @controller.recalculating?
            end

            # True once per terminal-resize burst; forces a redraw so the new
            # size applies even when the reader is idle on blocked input.
            def consume_pending_resize?
              @controller.consume_pending_resize?
            end

            # True once per render request posted via the controller (worker
            # threads wake the blocked read through the input self-pipe);
            # forces a redraw on this thread so the result becomes visible.
            def consume_render_request?
              @controller.consume_render_request?
            end

            # Applies async results (e.g. translations) on this thread; a
            # positive count forces a redraw so the result becomes visible.
            def drain_async_results
              @controller.drain_async_results.to_i
            end

            # Keep polling while async work is in flight so its result can be
            # drained and painted without waiting for a keypress.
            def async_work_pending?
              @controller.async_work_pending?
            end

            # While a search-result landing highlight is live, keep redrawing so its
            # orange background can blink, even when the reader is otherwise idle.
            def search_landing_active?
              highlight = @reader_state.search_landing_highlight
              return false unless highlight.is_a?(Hash)

              expires_at = landing_highlight_expires_at(highlight)
              expires_at ? monotonic_now < expires_at : false
            end

            def landing_highlight_expires_at(highlight)
              symbolized = highlight.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
              value = symbolized[:expires_at]
              value&.to_f
            end

            def read_iteration_keys(notification_active, blink_active)
              return @controller.read_input_keys unless notification_active || blink_active

              @controller.read_input_keys(timeout: blink_poll_interval(notification_active))
            end

            def idle_iteration?(keys, notification_active, blink_active)
              return false unless keys.empty?

              @controller.draw_screen if notification_active || blink_active
              true
            end

            def immediate_exit
              log_debug('reader.event_loop.immediate_exit', reason: 'running? was false at loop start')
              nil
            end

            def blink_poll_interval(notification_active)
              notification_active ? NOTIFICATION_POLL_INTERVAL : BLINK_POLL_INTERVAL
            end

            def log_debug(event, **data)
              @controller.logger&.debug(event, **data)
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
