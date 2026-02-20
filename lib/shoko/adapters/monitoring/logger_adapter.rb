# frozen_string_literal: true

require 'json'
require 'time'
require_relative '../../core/ports/outbound/logging'

module Shoko
  module Adapters
    module Monitoring
      # Instance-based logger that implements the Logging port.
      # Fully self-contained — does not delegate to any static/class-level singleton.
      class LoggerAdapter
        include Core::Ports::Outbound::Logging

        LEVELS = {
          debug: 0,
          info: 1,
          warn: 2,
          error: 3,
          fatal: 4,
        }.freeze

        attr_reader :level, :output

        def initialize(level: :info, output: nil)
          @level = level || :info
          @output = output || $stderr
        end

        def level=(new_level)
          @level = new_level || :info
        end

        def output=(new_output)
          @output = new_output || $stderr
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

        def log(severity, message, metadata)
          return if LEVELS[severity] < LEVELS[@level]

          entry = build_log_entry(severity, message, metadata)
          @output.puts(entry)
        rescue StandardError
          # Logging should never crash the application
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
        rescue StandardError
          value.to_s
        end
      end
    end
  end
end
