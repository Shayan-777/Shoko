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

              while running?
                notification_active = toast_message_active?
                blink_active = annotation_editor_active? || search_landing_active?
                keys = read_iteration_keys(notification_active, blink_active)
                record_tti(startup_reference, keys)
                next if idle_iteration?(keys, notification_active, blink_active)

                @controller.dispatch_input_keys(keys)
                @controller.draw_screen
              end

              log_debug('reader.event_loop.exit', reason: 'running? became false')
            end

            private

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
