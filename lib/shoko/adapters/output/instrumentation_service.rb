# frozen_string_literal: true

require_relative '../base_adapter'
require_relative '../../core/ports/instrumentation'

module Shoko
  module Adapters::Output
    # Provides a single facade for performance monitoring and tracing so that
    # higher layers do not talk to infrastructure modules directly.
    class InstrumentationService < Shoko::Adapters::BaseAdapter
      include Shoko::Core::Ports::Instrumentation

      # @param performance_monitor [Object, nil] Optional performance monitor
      # @param perf_tracer [Object, nil] Optional performance tracer
      # @param logger [Object, nil] Optional logger
      def initialize(performance_monitor: nil, perf_tracer: nil, logger: nil)
        super(logger: logger)
        @monitor = performance_monitor
        @tracer = perf_tracer
      end

      def measure(metric, &)
        raise ArgumentError, 'block required for #measure' unless block_given?

        tracer = @tracer if @tracer.respond_to?(:measure)
        monitor = @monitor if @monitor.respond_to?(:time)

        if tracer && monitor
          tracer.measure(metric) { monitor.time(metric, &) }
        elsif tracer
          tracer.measure(metric, &)
        elsif monitor
          monitor.time(metric, &)
        else
          yield
        end
      end

      def time(metric, &)
        measure(metric, &)
      end

      def annotate(payload)
        return unless @tracer.respond_to?(:annotate)

        @tracer.annotate(payload)
      end

      def record_metric(name, value, count = 1)
        @monitor&.record_metric(name, value, count)
      end

      def record_trace(metric, value)
        @tracer&.record(metric, value)
      end

      def complete_trace(**payload)
        @tracer&.complete(**payload)
      end

      def cancel_trace
        @tracer&.cancel
      end

      def start_trace(path)
        @tracer.respond_to?(:start_open) ? @tracer.start_open(path) : nil
      end
    end
  end
end
