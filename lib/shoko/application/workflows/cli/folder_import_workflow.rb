# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Cli
        # Coordinates directory discovery and batch cache imports for CLI usage.
        class FolderImportWorkflow
          GROUP_ORDER = %i[epub pdf fb2 kindle rtf].freeze

          DocumentCandidate = Data.define(:path, :format_group, :format_extension)
          DiscoveryReport = Data.define(:directory_path, :documents, :counts_by_group, :total_count)
          ImportFailure = Data.define(:path, :error_class, :error_message)
          ImportReport = Data.define(:total_count, :imported_count, :skipped_count, :failed_count, :failures,
                                     :elapsed_seconds)

          def initialize(scanner:, importer:, clock:, logger: nil)
            raise ArgumentError, 'scanner is required' unless scanner&.respond_to?(:scan)
            raise ArgumentError, 'importer is required' unless importer&.respond_to?(:import)
            raise ArgumentError, 'clock is required' unless clock&.respond_to?(:monotonic_now)

            @scanner = scanner
            @importer = importer
            @clock = clock
            @logger = logger
          end

          def discover(directory_path, recursive: true, skip_hidden: true)
            root = File.expand_path(directory_path.to_s)
            raw_documents = Array(@scanner.scan(root, recursive: recursive, skip_hidden: skip_hidden))
            documents = raw_documents.filter_map { |entry| build_candidate(entry) }
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
            selected = Array(documents).filter_map { |entry| build_candidate(entry) }
            total = selected.length
            imported_count = 0
            skipped_count = 0
            failed_count = 0
            failures = []
            started_at = monotonic_now

            selected.each_with_index do |document, index|
              path = document.path

              begin
                status = normalize_import_status(@importer.import(path))
                if status == :skipped
                  skipped_count += 1
                else
                  imported_count += 1
                end
                yield(done: index + 1, total: total, path: path, status: status) if block_given?
              rescue StandardError => e
                failed_count += 1
                failures << ImportFailure.new(path: path, error_class: e.class.to_s, error_message: e.message.to_s)
                @logger&.error('folder_import.file_failed', path: path, error: e.message)
                yield(done: index + 1, total: total, path: path, status: :failed) if block_given?
              end
            end

            ImportReport.new(
              total_count: total,
              imported_count: imported_count,
              skipped_count: skipped_count,
              failed_count: failed_count,
              failures: failures,
              elapsed_seconds: monotonic_now - started_at
            )
          end

          private

          def build_candidate(entry)
            path = read_field(entry, :path)
            return nil if path.to_s.strip.empty?

            extension = normalize_extension(read_field(entry, :format_extension), path)
            group = normalize_group(read_field(entry, :format_group) || group_for_extension(extension))

            DocumentCandidate.new(
              path: path,
              format_group: group,
              format_extension: extension || ''
            )
          end

          def read_field(entry, key)
            return entry.public_send(key) if entry.respond_to?(key)
            return entry[key] if entry.is_a?(Hash) && entry.key?(key)
            return entry[key.to_s] if entry.is_a?(Hash)

            nil
          end

          def group_for_extension(extension)
            case extension.to_s.downcase
            when '.epub' then :epub
            when '.pdf' then :pdf
            when '.fb2', '.fb2.zip' then :fb2
            when '.mobi', '.azw', '.azw3' then :kindle
            when '.rtf' then :rtf
            else
              nil
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

            basename = File.basename(path.to_s).downcase
            return '.fb2.zip' if basename.end_with?('.fb2.zip')

            File.extname(path.to_s).downcase
          end

          def normalize_import_status(result)
            status = if result.is_a?(Hash)
                       result[:status] || result['status']
                     else
                       result
                     end

            status.to_sym == :skipped ? :skipped : :imported
          rescue StandardError
            :imported
          end

          def default_counts
            GROUP_ORDER.each_with_object({}) { |group, acc| acc[group] = 0 }
          end

          def monotonic_now
            @clock.monotonic_now.to_f
          rescue StandardError
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end
      end
    end
  end
end
