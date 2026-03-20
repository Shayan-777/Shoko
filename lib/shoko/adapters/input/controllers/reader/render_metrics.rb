# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Tracks startup rendering milestones and records first-paint metrics.
          class RenderMetrics
            def initialize(instrumentation:, metrics_start_time_reader:, document_reader:, clock:)
              @instrumentation = instrumentation
              @metrics_start_time_reader = metrics_start_time_reader
              @document_reader = document_reader
              raise ArgumentError, 'clock is required' if clock.nil?

              @clock = clock
            end

            def perform_first_paint(draw_screen:)
              @instrumentation&.time('render.first_paint') { draw_screen.call }
              metrics_start_time = @metrics_start_time_reader.call
              unless metrics_start_time
                @instrumentation&.cancel_trace
                return
              end

              first_paint_completed_at = monotonic_now
              ttfp = first_paint_completed_at - metrics_start_time
              record_first_paint_metrics(ttfp)
            end

            private

            def cache_hit?
              doc = @document_reader.call
              doc&.cached? == true
            end

            def record_first_paint_metrics(ttfp)
              @instrumentation&.record_metric('render.first_paint.ttfp', ttfp, 0)
              @instrumentation&.record_trace('render.first_paint.ttfp', ttfp)
              @instrumentation&.complete_trace(open_type: cache_hit? ? 'warm' : 'cold', total_duration: ttfp)
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
