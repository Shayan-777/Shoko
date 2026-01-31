# frozen_string_literal: true

require 'optparse'
require 'fileutils'

module Shoko
  # The command-line interface for the Shoko application.
  class CLI
    class << self
      def run(argv = ARGV)
        options, args = parse_options(argv)
        log_config = build_log_config(options)

        Application::UnifiedApplication.new(args.first, log_config: log_config).run
      end

      private

      def parse_options(argv)
        options = default_options
        parser = OptionParser.new
        configure_parser(parser, options)
        parser.parse!(argv)
        [options, argv]
      end

      def default_options
        { debug: false, log_path: nil, log_level: nil, profile_path: nil }
      end

      def configure_parser(parser, options)
        parser.banner = 'Usage: shoko [options] [file]'
        parser.on('-d', '--debug', 'Enable debug logging') { options[:debug] = true }
        parser.on('--log PATH', 'Write JSON logs to PATH instead of discarding output') do |path|
          options[:log_path] = path
        end
        parser.on('--log-level LEVEL', 'Set log level (debug, info, warn, error, fatal)') do |level|
          options[:log_level] = level
        end
        parser.on('--profile PATH', 'Write a concise performance profile to PATH') do |path|
          options[:profile_path] = path
        end
        parser.on('-h', '--help', 'Prints this help') do
          puts parser
          exit
        end
      end

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

        path = (options[:log_path] || env_log_path).to_s.strip
        return [IO::NULL, nil] if path.empty?

        ensure_log_directory(path)
        file = File.open(path, 'a')
        file.sync = true
        [file, file]
      rescue StandardError
        [IO::NULL, nil]
      end

      def ensure_log_directory(path)
        FileUtils.mkdir_p(File.dirname(path))
      end

      def logger_level(options)
        return :debug if debug_enabled?(options)

        configured_level = options[:log_level] || env_log_level
        normalize_log_level(configured_level) || :error
      end

      def normalize_log_level(level)
        value = level.to_s.strip.downcase
        return nil if value.empty?

        %w[debug info warn error fatal].include?(value) ? value.to_sym : nil
      end

      def debug_enabled?(options)
        return true if options[:debug]

        value = ENV.fetch('DEBUG', '').to_s.strip.downcase
        return false if value.empty?

        !%w[0 false off no].include?(value)
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
      rescue StandardError => e
        Kernel.warn("[shoko] Failed to close log file: #{e.class}: #{e.message}")
      end
    end
  end
end
