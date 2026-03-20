# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Cli
        class FolderImportWorkflow
          # Import-run bookkeeping and progress emission helpers.
          module ImportRunSupport
            private

            def start_import_run(selected)
              {
                total: selected.length,
                imported_count: 0,
                skipped_count: 0,
                failed_count: 0,
                failures: [],
                started_at: monotonic_now,
              }
            end

            def process_import_document(run, document, index, progress_notifier)
              status = import_status_for(document, index, run[:total], progress_notifier)
              record_import_status(run, status)
              notify_import_completion(progress_notifier, import_progress(run, index, document.path, status))
            rescue Shoko::FileNotFoundError, Shoko::CacheLoadError, Shoko::MalformedBookInputError => e
              run[:failed_count] += 1
              run[:failures] << build_import_failure(document, e)
              notify_import_completion(progress_notifier, import_progress(run, index, document.path, :failed))
            end

            def import_status_for(document, index, total, progress_notifier)
              reporter = progress_reporter_for(index, total, document.path, &progress_notifier) if progress_notifier
              normalize_import_status(import_document(document.path, progress_reporter: reporter))
            end

            def record_import_status(run, status)
              counter = status == :skipped ? :skipped_count : :imported_count
              run[counter] += 1
            end

            def notify_import_completion(notifier, progress)
              return unless notifier

              notify_progress(notifier, **progress)
            end

            def import_progress(run, index, path, status)
              {
                done: index + 1,
                total: run[:total],
                path: path,
                status: status,
                progress: final_progress(index + 1, run[:total]),
              }
            end

            def finish_import_run(run)
              ImportReport.new(
                total_count: run[:total],
                imported_count: run[:imported_count],
                skipped_count: run[:skipped_count],
                failed_count: run[:failed_count],
                failures: run[:failures],
                elapsed_seconds: monotonic_now - run[:started_at]
              )
            end
          end
        end
      end
    end
  end
end
