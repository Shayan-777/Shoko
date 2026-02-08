# frozen_string_literal: true

module Shoko
  module Application
    module MainMenu
      # Encapsulates loading-state updates while a book is preprocessed.
      class MenuProgressPresenter
        MIN_PROGRESS_DELTA = 0.01

        def initialize(state)
          @state = state
          @last_message = nil
          @last_progress = nil
        end

        def show(path:, index:, mode:)
          @last_message = 'Preparing book...'
          @last_progress = 0.0
          dispatch(
            loading_active: true,
            loading_path: path,
            loading_progress: 0.0,
            loading_index: index,
            loading_mode: mode,
            loading_message: @last_message
          )
        end

        def update(done:, total:)
          progress = Shoko::Core::Services::ProgressHelper.ratio(done, total)
          update_status(progress: progress)
        end

        def update_message(message)
          update_status(message: message)
        end

        def set_progress(progress)
          update_status(progress: progress)
        end

        def update_status(message: nil, progress: nil)
          updates = {}

          if message && message != @last_message
            updates[:loading_message] = message
            @last_message = message
          end

          unless progress.nil?
            normalized = progress.to_f.clamp(0.0, 1.0)
            if @last_progress.nil? || (normalized - @last_progress).abs >= MIN_PROGRESS_DELTA
              updates[:loading_progress] = normalized
              @last_progress = normalized
            end
          end

          dispatch(updates) unless updates.empty?
          !updates.empty?
        end

        def clear
          @last_message = nil
          @last_progress = nil
          dispatch(
            loading_active: false,
            loading_path: nil,
            loading_progress: nil,
            loading_index: nil,
            loading_mode: nil,
            loading_message: nil
          )
        end

        private

        def dispatch(payload)
          @state.update(payload.transform_keys { |field| [:menu, field] })
        end
      end
    end
  end
end
