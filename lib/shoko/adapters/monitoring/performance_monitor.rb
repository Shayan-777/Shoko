# frozen_string_literal: true

module Shoko
  module Adapters::Monitoring
    # Performance monitoring for the application.
    # Tracks execution times, memory usage, and provides profiling capabilities.
    #
    # @example Timing a block
    #   PerformanceMonitor.time("epub_parsing") do
    #     EPUBDocument.new(path)
    #   end
    #
    # @example Getting metrics
    #   puts PerformanceMonitor.metrics
    class PerformanceMonitor
      class << self
        # Storage for performance metrics
        def metrics
          @metrics ||= Hash.new { |h, k| h[k] = [] }
        end

        # Time a block of code
        #
        # @param label [String] Label for the timing
        # @yield Block to time
        # @return [Object] Result of the block
        def time(label)
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          start_memory = current_memory_usage

          result = yield

          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end_memory = current_memory_usage

          duration = end_time - start_time
          memory_delta = end_memory - start_memory

          record_metric(label, duration, memory_delta)

          result
        end

        # Record a metric
        #
        # @param label [String] Metric label
        # @param duration [Float] Duration in seconds
        # @param memory_delta [Integer] Memory change in bytes
        def record_metric(label, duration, memory_delta)
          metrics[label] << ({
            timestamp: Time.now,
            duration:,
            memory_delta:,
          })

          # Log slow operations
          return unless duration > 1.0

          Shoko::Adapters::Monitoring::Logger.warn('Slow operation detected',
                                                   label:,
                                                   duration: "#{(duration * 1000).round(2)}ms")
        end

        # Get statistics for a metric
        #
        # @param label [String] Metric label
        # @return [Hash] Statistics
        def stats(label)
          data = metrics[label]
          return nil if data.empty?

          calculate_statistics(data)
        end

        # Clear all metrics
        def clear
          @metrics = nil
        end

        private

        def calculate_statistics(data)
          durations = data.map { |m| m[:duration] }

          {
            count: data.size,
            total: durations.sum,
            average: calculate_average(durations),
            min: durations.min,
            max: durations.max,
            last: durations.last,
          }
        end

        def calculate_average(durations)
          durations.sum / durations.size
        end

        # Get current memory usage in bytes
        #
        # @return [Integer] Memory usage
        def current_memory_usage
          # This is a simplified version - in production you might use
          # more sophisticated memory profiling
          GC.stat[:total_allocated_objects] * 40 # Rough estimate
        end
      end
    end
  end
end
