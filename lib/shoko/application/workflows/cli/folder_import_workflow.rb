# frozen_string_literal: true

require_relative '../../../application/ports/outbound/folder_scanner'
require_relative '../../../application/ports/outbound/folder_importer'
require_relative '../../../application/ports/outbound/clock'
require_relative '../../../application/ports/outbound/path_ops'
require_relative 'folder_import_progress_reporter'
require_relative 'folder_import_workflow/import_run_support'

module Shoko
  module Application
    module Workflows
      module Cli
        # Coordinates directory discovery and batch cache imports for CLI usage.
        class FolderImportWorkflow
          include ImportRunSupport

          GROUP_ORDER = %i[epub pdf fb2 kindle rtf].freeze

          DocumentCandidate = Shoko::Application::Ports::Outbound::FolderScanner::Entry
          DiscoveryReport = Data.define(:directory_path, :documents, :counts_by_group, :total_count)
          ImportFailure = Data.define(:path, :error_class, :error_message)
          ImportReport = Data.define(:total_count,
                                     :imported_count,
                                     :skipped_count,
                                     :failed_count,
                                     :failures,
                                     :elapsed_seconds)
          KEYWORD_PARAMETER_KINDS = %i[key keyreq keyrest].freeze
          PROGRESS_PAYLOAD_KEYS = Shoko::Application::Workflows::Cli::FolderImportProgressReporter::PAYLOAD_KEYS
          private_constant :KEYWORD_PARAMETER_KINDS, :PROGRESS_PAYLOAD_KEYS

          def initialize(scanner:, importer:, clock:, path_ops:, logger: nil)
            unless scanner.is_a?(Shoko::Application::Ports::Outbound::FolderScanner)
              raise ArgumentError, 'scanner must implement Application::Ports::Outbound::FolderScanner'
            end
            unless importer.is_a?(Shoko::Application::Ports::Outbound::FolderImporter)
              raise ArgumentError, 'importer must implement Application::Ports::Outbound::FolderImporter'
            end
            unless clock.is_a?(Shoko::Application::Ports::Outbound::Clock)
              raise ArgumentError, 'clock must implement Application::Ports::Outbound::Clock'
            end
            unless path_ops.is_a?(Shoko::Application::Ports::Outbound::PathOps)
              raise ArgumentError, 'path_ops must implement Application::Ports::Outbound::PathOps'
            end

            @scanner = scanner
            @importer = importer
            @clock = clock
            @path_ops = path_ops
            @logger = logger
          end

          def discover(directory_path, recursive: true, skip_hidden: true)
            root = @path_ops.expand_path(directory_path.to_s)
            documents = normalized_discovery_documents(root, recursive: recursive, skip_hidden: skip_hidden)
            DiscoveryReport.new(
              directory_path: root,
              documents: documents,
              counts_by_group: counts_by_group_for(documents),
              total_count: documents.length
            )
          end

          def import(documents, &progress_notifier)
            selected = Array(documents).map { |entry| normalize_candidate(entry) }
            run = start_import_run(selected)

            selected.each_with_index do |document, index|
              process_import_document(run, document, index, progress_notifier)
            end

            finish_import_run(run)
          end

          private

          def normalize_candidate(entry)
            unless entry.is_a?(DocumentCandidate)
              raise ArgumentError, "Expected #{DocumentCandidate}, got #{entry.class}"
            end

            path = entry.path
            raise ArgumentError, 'candidate path cannot be blank' if path.to_s.strip.empty?

            extension = normalize_extension(entry.format_extension, path)
            group = normalize_group(entry.format_group || group_for_extension(extension))

            DocumentCandidate.new(path: path, format_group: group, format_extension: extension || '')
          end

          def group_for_extension(extension)
            case extension.to_s.downcase
            when '.epub' then :epub
            when '.pdf' then :pdf
            when '.fb2', '.fb2.zip' then :fb2
            when '.mobi', '.azw', '.azw3' then :kindle
            when '.rtf' then :rtf
            end
          end

          def normalize_group(group)
            value = group.to_s.strip.downcase
            return :unknown if value.empty?

            value.tr('-', '_').to_sym
          end

          def normalize_extension(extension, path)
            value = extension.to_s.strip.downcase
            return value unless value.empty?

            basename = @path_ops.basename(path.to_s).downcase
            return '.fb2.zip' if basename.end_with?('.fb2.zip')

            @path_ops.extname(path.to_s).downcase
          end

          def normalize_import_status(result)
            case result
            when :imported, :skipped
              result
            else
              raise ArgumentError, "Invalid folder import status: #{result.inspect}"
            end
          end

          def build_import_failure(document, error)
            ImportFailure.new(
              path: document.path.to_s,
              error_class: error.class.name.to_s,
              error_message: failure_message_for(error, document.path.to_s)
            )
          end

          def failure_message_for(error, document_path)
            message = error.message.to_s
            error_path = case error
                         when Shoko::MalformedBookInputError
                           path = error.file_path.to_s
                           path.strip.empty? ? document_path : path
                         else
                           document_path
                         end

            malformed_prefix = "Malformed book input at #{error_path}: "
            return message.delete_prefix(malformed_prefix) if message.start_with?(malformed_prefix)
            return 'File not found' if message == "File not found: #{error_path}"

            message
          end

          def default_counts
            GROUP_ORDER.to_h { |group| [group, 0] }
          end

          def normalized_discovery_documents(root, recursive:, skip_hidden:)
            Array(@scanner.scan(root, recursive: recursive, skip_hidden: skip_hidden))
              .map { |entry| normalize_candidate(entry) }
              .sort_by { |entry| entry.path.to_s.downcase }
          end

          def counts_by_group_for(documents)
            documents.each_with_object(default_counts) do |document, counts|
              group = normalize_group(document.format_group)
              counts[group] ||= 0
              counts[group] += 1
            end
          end

          def monotonic_now
            @clock.monotonic_now.to_f
          end

          def import_document(path, progress_reporter:)
            parameters = @importer.method(:import).parameters
            if supports_progress_reporter_keyword?(parameters)
              return @importer.import(path, progress_reporter: progress_reporter)
            end

            @importer.import(path)
          end

          def progress_reporter_for(index, total, path, &notifier)
            FolderImportProgressReporter.new(
              document_index: index,
              total_documents: total,
              path: path,
              notifier: notifier
            )
          end

          def final_progress(done, total)
            return 1.0 unless total.to_i.positive?

            done.to_f / total
          end

          def notify_progress(notifier, **payload)
            supported = supported_progress_keywords(notifier)
            notifier.call(**payload.slice(*supported))
          end

          def supported_progress_keywords(notifier)
            parameters = notifier.parameters
            return PROGRESS_PAYLOAD_KEYS if parameters.any? { |kind, _name| kind == :keyrest }

            parameters.filter_map do |kind, name|
              next unless KEYWORD_PARAMETER_KINDS.include?(kind)

              name
            end
          end

          def supports_progress_reporter_keyword?(parameters)
            parameters.any? { |kind, name| KEYWORD_PARAMETER_KINDS.include?(kind) && name == :progress_reporter } ||
              parameters.any? { |kind, _name| kind == :keyrest }
          end
        end
      end
    end
  end
end
