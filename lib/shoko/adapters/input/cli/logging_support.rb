# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      class CLI
        # Logging/profile configuration helpers for CLI startup.
        module LoggingSupport
          private

          def build_log_config(options)
            output, log_file = logger_output(options)
            register_log_file_closer(log_file)

            {
              level: logger_level(options),
              output: output,
              profile_path: resolve_profile_path(options),
              debug: debug_enabled?(options),
            }
          end

          def resolve_profile_path(options)
            path = (options[:profile_path] || env_profile_path).to_s.strip
            path.empty? ? nil : path
          end

          def logger_output(options)
            return [$stdout, nil] if debug_enabled?(options)

            explicit_path = options[:log_path].to_s.strip
            path = explicit_path.empty? ? env_log_path : explicit_path
            return [IO::NULL, nil] if path.empty?

            ensure_log_directory(path)
            file = File.open(path, 'a', &:dup)
            file.sync = true
            [file, file]
          rescue IOError, SystemCallError, ArgumentError => e
            warn_log_path_fallback(path, e) unless explicit_path.empty?
            [IO::NULL, nil]
          end

          def warn_log_path_fallback(path, error)
            Kernel.warn(
              "[shoko] Failed to open log path '#{path}'; falling back to null logger: " \
              "#{error.class}: #{error.message}"
            )
          end

          def ensure_log_directory(path)
            require 'fileutils'
            FileUtils.mkdir_p(File.dirname(path))
          end

          def logger_level(options)
            return :debug if debug_enabled?(options)

            normalize_log_level(options[:log_level] || env_log_level) || :error
          end

          def normalize_log_level(level)
            value = level.to_s.strip.downcase
            return nil if value.empty?

            %w[debug info warn error fatal].include?(value) ? value.to_sym : nil
          end

          def debug_enabled?(options)
            return true if options[:debug]

            value = ENV.fetch('DEBUG', '').to_s.strip.downcase
            !value.empty? && !%w[0 false off no].include?(value)
          end

          def env_log_path
            ENV.fetch('SHOKO_LOG_PATH', '').to_s.strip
          end

          def env_log_level
            ENV.fetch('SHOKO_LOG_LEVEL', '').to_s.strip
          end

          def env_profile_path
            ENV.fetch('SHOKO_PROFILE_PATH', '').to_s.strip
          end

          def register_log_file_closer(log_file)
            return unless log_file

            at_exit { close_log_file(log_file) }
          end

          def close_log_file(log_file)
            return if log_file.closed?

            log_file.close
          rescue IOError, SystemCallError => e
            Kernel.warn("[shoko] Failed to close log file: #{e.class}: #{e.message}")
          end
        end
      end
    end
  end
end
