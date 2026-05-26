# frozen_string_literal: true

require 'optparse'
require_relative '../../shared/version'
require_relative '../../shared/errors'
require_relative '../../application/ports/outbound/folder_scanner'
require_relative '../runtime/process_control_adapter'
require_relative 'cli/directory_import_contract_support'
require_relative 'cli/directory_import_support'
require_relative 'cli/logging_support'

# Root namespace for the Shoko application.
module Shoko
  module Adapters
    module Input
      # Command-line entry adapter that parses argv and launches the application.
      class CLI
        FolderImportContext = Data.define(:workflow, :progress_presenter_factory)
        FolderImportDocument = Shoko::Application::Ports::Outbound::FolderScanner::Entry
        FolderDiscoveryReport = Data.define(:directory_path, :documents, :counts_by_group, :total_count)
        FolderImportFailure = Data.define(:path, :error_class, :error_message)
        FolderImportReport = Data.define(:total_count,
                                         :imported_count,
                                         :skipped_count,
                                         :failed_count,
                                         :failures,
                                         :elapsed_seconds)

        FORMAT_GROUP_ORDER = %i[epub pdf fb2 kindle rtf].freeze
        FORMAT_GROUP_LABELS = { epub: 'EPUB', pdf: 'PDF', fb2: 'FB2', kindle: 'Kindle', rtf: 'RTF' }.freeze
        MAX_FAILURE_LINES = 10

        class << self
          include DirectoryImportContractSupport
          include DirectoryImportSupport
          include LoggingSupport

          def run(argv = ARGV, app_factory:, process_control:, folder_import_factory: nil, input: $stdin,
                  output: $stdout)
            options, args = parse_options(argv)
            log_config = build_log_config(options)
            target_path, action = resolve_target_path(
              args.first,
              log_config: log_config,
              folder_import_factory: folder_import_factory,
              input: input,
              output: output
            )
            return if action == :exit

            app_factory.call(epub_path: target_path, log_config: log_config).run
          rescue Shoko::FatalExternalInputError => e
            emit_fatal_external_input_message(output, e)
            process_control.terminate(2)
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
            parser.banner = 'Usage: shoko [options] [file_or_directory]'
            parser.version = Shoko::VERSION
            configure_logging_options(parser, options)
            configure_help_option(parser)
          end

          def configure_logging_options(parser, options)
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
          end

          def configure_help_option(parser)
            parser.on('-h', '--help', 'Prints this help') do
              puts parser
              exit
            end
          end

          def directory_path?(path)
            File.directory?(path)
          end

          def resolve_target_path(target_path, log_config:, folder_import_factory:, input:, output:)
            return [target_path, nil] unless target_path && directory_path?(target_path) && folder_import_factory

            action = run_directory_import_session(
              target_path,
              log_config: log_config,
              folder_import_factory: folder_import_factory,
              input: input,
              output: output
            )
            [nil, action]
          end

          def emit_fatal_external_input_message(output, error)
            output.puts
            output.puts("[#{fatal_event_id_for(error)}] Fatal external input error: #{error.message}")
          end

          def fatal_event_id_for(error)
            case error
            when Shoko::MalformedBookInputError
              'fatal.external_input.book'
            when Shoko::MalformedMetadataInputError
              'fatal.external_input.metadata'
            when Shoko::MalformedDictionaryInputError
              'fatal.external_input.dictionary'
            else
              'fatal.external_input.unknown'
            end
          end
        end
      end
    end
  end
end
