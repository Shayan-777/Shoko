# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'
require_relative '../../application/ports/outbound/logging'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Monitoring
      # Instance-based logger that implements the Logging port.
      # Fully self-contained — does not delegate to any static/class-level singleton.
      class LoggerAdapter
        include Application::Ports::Outbound::Logging

        LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

        attr_reader :level, :output

        def initialize(level: :info, output: nil)
          @level = normalize_level(level)
          @owned_output = nil
          self.output = output
        end

        def level=(new_level)
          @level = normalize_level(new_level)
        end

        def output=(new_output)
          resolved, owned = resolve_output(new_output)
          close_owned_output!
          @output = resolved
          @owned_output = owned
        end

        def debug(message, **metadata)
          log(:debug, message, metadata)
        end

        def info(message, **metadata)
          log(:info, message, metadata)
        end

        def warn(message, **metadata)
          log(:warn, message, metadata)
        end

        def error(message, **metadata)
          log(:error, message, metadata)
        end

        def fatal(message, **metadata)
          log(:fatal, message, metadata)
        end

        def with_context(ctx)
          old_context = context.dup
          context.merge!(ctx)
          yield
        ensure
          Thread.current[:shoko_logger_context] = old_context
        end

        private

        def context
          Thread.current[:shoko_logger_context] ||= {}
        end

        def resolve_output(new_output)
          output = new_output || $stderr
          return [output, nil] if output.respond_to?(:puts)

          return open_output_path(output) if output.is_a?(String)

          raise ArgumentError, 'logger output must respond to puts or be a String path'
        end

        def open_output_path(path)
          normalized = path.to_s.strip
          raise ArgumentError, 'logger output path must not be empty' if normalized.empty?

          directory = File.dirname(normalized)
          FileUtils.mkdir_p(directory) unless directory.empty? || directory == '.'

          file = File.open(normalized, 'a', &:dup)
          file.sync = true
          [file, file]
        end

        def close_owned_output!
          return unless @owned_output
          return if @owned_output.closed?

          @owned_output.close
        ensure
          @owned_output = nil
        end

        def log(severity, message, metadata)
          return if LEVELS[severity] < LEVELS[@level]

          entry = build_log_entry(severity, message, metadata)
          @output.puts(entry)
        rescue StandardError => e
          report_logging_failure('log_write', e)
          nil
        end

        def build_log_entry(severity, message, metadata)
          {
            timestamp: Time.now.iso8601,
            severity: severity.upcase,
            message: normalize_string(message),
            context: sanitize_payload(context),
            metadata: sanitize_payload(metadata),
            thread_id: Thread.current.object_id,
          }.to_json
        end

        def sanitize_payload(value)
          case value
          when String
            normalize_string(value)
          when Hash
            value.each_with_object({}) do |(key, val), acc|
              safe_key = key.is_a?(String) ? normalize_string(key) : key
              acc[safe_key] = sanitize_payload(val)
            end
          when Array
            value.map { |item| sanitize_payload(item) }
          else
            value
          end
        end

        def normalize_string(value)
          str = value.to_s
          return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?

          str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?')
        rescue StandardError => e
          raise_logging_error('normalize_string', e)
        end

        def normalize_level(value)
          return :info if value.nil?

          normalized = value.to_s.strip.downcase
          normalized = 'info' if normalized.empty?
          level_key = normalized.to_sym
          return level_key if LEVELS.key?(level_key)

          raise ArgumentError, "invalid log level: #{value.inspect}"
        end

        def raise_logging_error(operation, error)
          raise error if error.is_a?(Shoko::Error)

          raise Shoko::LoggingError.new(operation, error.message)
        end

        def report_logging_failure(operation, error)
          Kernel.warn("Shoko logger #{operation} failed: #{error.class}: #{error.message}")
        # resilient-boundary
        rescue StandardError
          nil
        end
      end
    end
  end
end
