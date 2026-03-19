# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Loading-state helpers shared by pagination orchestration sessions.
        module PaginationOrchestratorLoadingStateSupport
          def progress_callback
            ->(done, total) { update_progress(done, total) }
          end

          def with_loading(message)
            begin_loading(message)
            yield
          ensure
            end_loading
          end

          def begin_loading(message)
            persist_view(loading_active: true, loading_message: message, loading_progress: 0.0)
          end

          def end_loading
            persist_view(loading_active: false, loading_message: nil)
          end

          def update_progress(done, total)
            progress = Shoko::Core::Services::ProgressHelper.ratio(done, total)
            persist_view(loading_progress: progress)
          end
        end
      end
    end
  end
end
