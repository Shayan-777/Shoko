# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      # Presents progress updates for CLI-only adapter-owned loading flows.
      class CLIProgressPresenter
        MIN_PROGRESS_DELTA = 0.01

        def initialize(renderer:)
          @renderer = renderer
          @last_message = nil
          @last_progress = nil
        end

        def start(message: 'Preparing book...')
          @last_message = message
          @last_progress = 0.0
          @renderer.render(message: @last_message, progress: @last_progress)
        end

        def update_status(message: nil, progress: nil)
          updates = false

          if message && message != @last_message
            @last_message = message
            updates = true
          end

          unless progress.nil?
            normalized = progress.to_f.clamp(0.0, 1.0)
            if @last_progress.nil? || (normalized - @last_progress).abs >= MIN_PROGRESS_DELTA
              @last_progress = normalized
              updates = true
            end
          end

          return false unless updates

          @renderer.render(message: @last_message, progress: @last_progress)
          true
        end

        def finish
          @renderer.clear
        end
      end
    end
  end
end
