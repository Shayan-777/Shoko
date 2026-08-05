# frozen_string_literal: true

module Shoko
  module Shared
    # Last-chance diagnostics for failure-containment boundaries.
    #
    # A callback, cleanup, or background-job failure is already on an error
    # path. Failure of the injected logger must never replace that error,
    # escape the containment boundary, or prevent mandatory completion work.
    module ResilientDiagnostics
      module_function

      def debug(logger, message, **metadata) = emit(logger, :debug, message, metadata)

      def info(logger, message, **metadata) = emit(logger, :info, message, metadata)

      def warn(logger, message, **metadata) = emit(logger, :warn, message, metadata)

      def error(logger, message, **metadata) = emit(logger, :error, message, metadata)

      def fatal(logger, message, **metadata) = emit(logger, :fatal, message, metadata)

      def emit(logger, severity, message, metadata = {})
        return false unless logger

        case severity
        when :debug then logger.debug(message, **metadata)
        when :info then logger.info(message, **metadata)
        when :warn then logger.warn(message, **metadata)
        when :error then logger.error(message, **metadata)
        when :fatal then logger.fatal(message, **metadata)
        else raise ArgumentError, "unsupported diagnostic severity: #{severity.inspect}"
        end
        true
      # resilient-boundary
      rescue StandardError
        contain_diagnostic_failure
        false
      end

      # There is deliberately no further logging here: this is the terminal
      # containment point reached precisely because diagnostics failed.
      def contain_diagnostic_failure
        nil
      end
    end
  end
end
