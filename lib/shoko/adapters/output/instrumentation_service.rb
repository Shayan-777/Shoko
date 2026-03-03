# frozen_string_literal: true

require_relative '../base_adapter'
require_relative '../../core/ports/outbound/instrumentation'

module Shoko
  module Adapters
    module Output
      # Provides a single facade for performance monitoring and tracing so that
      # higher layers do not talk to infrastructure modules directly.
      class InstrumentationService < Shoko::Adapters::BaseAdapter
        include Shoko::Core::Ports::Outbound::Instrumentation

        class NullMonitor
          def time(_metric)
            yield
          end

          def record_metric(_name, _value, _count = 1)
            nil
          end
        end

        class NullTracer
          def measure(_metric)
            yield
          end

          def annotate(_payload); end

          def record(_metric, _value); end

          def complete(**_payload); end

          def cancel; end

          def start_open(_path)
            nil
          end
        end

        # @param performance_monitor [Object, nil] Optional performance monitor
        # @param perf_tracer [Object, nil] Optional performance tracer
        # @param logger [Object, nil] Optional logger
        def initialize(performance_monitor: nil, perf_tracer: nil, logger: nil)
          super(logger: logger)
          @monitor = performance_monitor || NullMonitor.new
          @tracer = perf_tracer || NullTracer.new
        end

        def measure(metric, &)
          raise ArgumentError, 'block required for #measure' unless block_given?

          @tracer.measure(metric) { @monitor.time(metric, &) }
        end

        def time(metric, &)
          measure(metric, &)
        end

        def annotate(payload)
          @tracer.annotate(payload)
        end

        def record_metric(name, value, count = 1)
          @monitor.record_metric(name, value, count)
        end

        def record_trace(metric, value)
          @tracer.record(metric, value)
        end

        def complete_trace(**payload)
          @tracer.complete(**payload)
        end

        def cancel_trace
          @tracer.cancel
        end

        def start_trace(path)
          @tracer.start_open(path)
        end
      end
    end
  end
end
