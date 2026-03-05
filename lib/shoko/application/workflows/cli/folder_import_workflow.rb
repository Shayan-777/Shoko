# frozen_string_literal: true

require_relative '../../../core/ports/outbound/folder_scanner'
require_relative '../../../core/ports/outbound/folder_importer'
require_relative '../../../core/ports/outbound/clock'
require_relative '../../../core/ports/outbound/path_ops'

module Shoko
  module Application
    module Workflows
      module Cli
        # Coordinates directory discovery and batch cache imports for CLI usage.
        class FolderImportWorkflow
          GROUP_ORDER = %i[epub pdf fb2 kindle rtf].freeze

          DocumentCandidate = Shoko::Core::Ports::Outbound::FolderScanner::Entry
          DiscoveryReport = Data.define(:directory_path, :documents, :counts_by_group, :total_count)
          ImportFailure = Data.define(:path, :error_class, :error_message)
          ImportReport = Data.define(:total_count, :imported_count, :skipped_count, :failed_count, :failures,
                                     :elapsed_seconds)

          def initialize(scanner:, importer:, clock:, path_ops:, logger: nil)
            unless scanner.is_a?(Shoko::Core::Ports::Outbound::FolderScanner)
              raise ArgumentError, 'scanner must implement Core::Ports::Outbound::FolderScanner'
            end
            unless importer.is_a?(Shoko::Core::Ports::Outbound::FolderImporter)
              raise ArgumentError, 'importer must implement Core::Ports::Outbound::FolderImporter'
            end
            unless clock.is_a?(Shoko::Core::Ports::Outbound::Clock)
              raise ArgumentError, 'clock must implement Core::Ports::Outbound::Clock'
            end
            unless path_ops.is_a?(Shoko::Core::Ports::Outbound::PathOps)
              raise ArgumentError, 'path_ops must implement Core::Ports::Outbound::PathOps'
            end

            @scanner = scanner
            @importer = importer
            @clock = clock
            @path_ops = path_ops
            @logger = logger
          end

          def discover(directory_path, recursive: true, skip_hidden: true)
            root = @path_ops.expand_path(directory_path.to_s)
            raw_documents = Array(@scanner.scan(root, recursive: recursive, skip_hidden: skip_hidden))
            documents = raw_documents.map { |entry| normalize_candidate(entry) }
                                     .sort_by { |entry| entry.path.to_s.downcase }

            counts = default_counts
            documents.each do |document|
              group = normalize_group(document.format_group)
              counts[group] ||= 0
              counts[group] += 1
            end

            DiscoveryReport.new(
              directory_path: root,
              documents: documents,
              counts_by_group: counts,
              total_count: documents.length
            )
          end

          def import(documents)
            selected = Array(documents).map { |entry| normalize_candidate(entry) }
            total = selected.length
            imported_count = 0
            skipped_count = 0
            started_at = monotonic_now

            selected.each_with_index do |document, index|
              path = document.path

              status = normalize_import_status(@importer.import(path))
              if status == :skipped
                skipped_count += 1
              else
                imported_count += 1
              end
              yield(done: index + 1, total: total, path: path, status: status) if block_given?
            end

            ImportReport.new(
              total_count: total,
              imported_count: imported_count,
              skipped_count: skipped_count,
              failed_count: 0,
              failures: [],
              elapsed_seconds: monotonic_now - started_at
            )
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

            DocumentCandidate.new(
              path: path,
              format_group: group,
              format_extension: extension || ''
            )
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

          def default_counts
            GROUP_ORDER.to_h { |group| [group, 0] }
          end

          def monotonic_now
            @clock.monotonic_now.to_f
          end
        end
      end
    end
  end
end
