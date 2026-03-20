# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      class CLI
        # Contract coercion helpers for folder import workflow responses.
        module DirectoryImportContractSupport
          private

          def coerce_folder_import_context(raw_context)
            FolderImportContext.new(
              workflow: raw_context.workflow,
              progress_presenter_factory: raw_context.progress_presenter_factory
            )
          rescue ArgumentError => e
            raise ArgumentError, "folder import context contract violation: #{e.message}"
          end

          def coerce_import_document(raw_document)
            FolderImportDocument.new(
              path: raw_document.path.to_s,
              format_group: normalize_group_value(raw_document.format_group),
              format_extension: raw_document.format_extension.to_s
            )
          rescue ArgumentError => e
            raise ArgumentError, "folder import document contract violation: #{e.message}"
          end

          def coerce_discovery_report(raw_report)
            FolderDiscoveryReport.new(
              directory_path: raw_report.directory_path.to_s,
              documents: Array(raw_report.documents).map { |document| coerce_import_document(document) },
              counts_by_group: normalize_counts_by_group(raw_report.counts_by_group),
              total_count: Integer(raw_report.total_count)
            )
          rescue TypeError => e
            raise ArgumentError, "invalid folder discovery report: #{e.message}"
          rescue ArgumentError => e
            raise ArgumentError, "folder discovery report contract violation: #{e.message}"
          end

          def normalize_counts_by_group(raw_counts)
            raise ArgumentError, 'counts_by_group must be a Hash' unless raw_counts.is_a?(Hash)

            raw_counts.each_with_object({}) do |(raw_group, raw_count), acc|
              acc[normalize_group_value(raw_group)] = Integer(raw_count)
            end
          rescue ArgumentError, TypeError => e
            raise ArgumentError, "invalid counts_by_group value: #{e.message}"
          end

          def coerce_import_report(raw_report)
            FolderImportReport.new(
              total_count: Integer(raw_report.total_count),
              imported_count: Integer(raw_report.imported_count),
              skipped_count: Integer(raw_report.skipped_count),
              failed_count: Integer(raw_report.failed_count),
              failures: Array(raw_report.failures).map { |failure| coerce_import_failure(failure) },
              elapsed_seconds: raw_report.elapsed_seconds.to_f
            )
          rescue TypeError => e
            raise ArgumentError, "invalid folder import report: #{e.message}"
          rescue ArgumentError => e
            raise ArgumentError, "folder import report contract violation: #{e.message}"
          end

          def coerce_import_failure(raw_failure)
            FolderImportFailure.new(
              path: raw_failure.path.to_s,
              error_class: raw_failure.error_class.to_s,
              error_message: raw_failure.error_message.to_s
            )
          rescue ArgumentError => e
            raise ArgumentError, "folder import failure contract violation: #{e.message}"
          end
        end
      end
    end
  end
end
