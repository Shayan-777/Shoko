# frozen_string_literal: true

require_relative '../../core/services/base_service'

module Shoko
  module Adapters::Output
    # Provides a single facade for performance monitoring and tracing so that
    # higher layers do not talk to infrastructure modules directly.
    class InstrumentationService < BaseService
      def initialize(dependencies)
        super
        @monitor = resolve_optional(:performance_monitor)
        @tracer  = resolve_optional(:perf_tracer)
      end

      def time(metric, &)
        raise ArgumentError, 'block required for #time' unless block_given?
        return yield unless @monitor.respond_to?(:time)

        @monitor.time(metric, &)
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

      private

      def resolve_optional(name)
        resolve(name)
      rescue StandardError
        nil
      end
    end
  end
end
