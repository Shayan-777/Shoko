# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Cli
        # Adapts nested per-document import progress into workflow-level progress updates.
        #
        # The notifier contract: a callable accepting the full PAYLOAD_KEYS
        # keyword set. Notifiers are internal (the CLI supplies them), so the
        # payload is passed whole — no signature adaptation.
        class FolderImportProgressReporter
          PAYLOAD_KEYS = %i[done total path status message progress].freeze

          def initialize(document_index:, total_documents:, path:, notifier:)
            @document_index = document_index
            @total_documents = total_documents
            @path = path
            @notifier = notifier
          end

          def update_status(message: nil, progress: nil)
            notify_progress(
              done: @document_index + 1,
              total: @total_documents,
              path: @path,
              status: :running,
              message: message,
              progress: aggregate_progress(progress)
            )
          end

          private

          def aggregate_progress(progress)
            normalized = progress.nil? ? 0.0 : progress.to_f.clamp(0.0, 1.0)
            ((@document_index.to_f + normalized) / [@total_documents.to_f, 1.0].max).clamp(0.0, 1.0)
          end

          def notify_progress(**payload)
            @notifier.call(**payload)
          end
        end
      end
    end
  end
end
