# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_workflow_state_writer'

module Shoko
  module Application
    module Workflows
      module Menu
        # Encapsulates loading-state updates while a book is preprocessed.
        class MenuProgressPresenter
          MIN_PROGRESS_DELTA = 0.01

          def initialize(menu_state_writer)
            unless menu_state_writer.is_a?(Shoko::Core::Ports::Outbound::MenuWorkflowStateWriter)
              raise ArgumentError, 'menu_state_writer must implement Core::Ports::Outbound::MenuWorkflowStateWriter'
            end

            @menu_state_writer = menu_state_writer
            @last_message = nil
            @last_progress = nil
          end

          def show(path:, index:, mode:)
            @last_message = 'Preparing book...'
            @last_progress = 0.0
            @menu_state_writer.set_loading_state(
              active: true,
              path: path,
              progress: 0.0,
              index: index,
              mode: mode,
              message: @last_message
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
              updates[:message] = message
              @last_message = message
            end

            unless progress.nil?
              normalized = progress.to_f.clamp(0.0, 1.0)
              if @last_progress.nil? || (normalized - @last_progress).abs >= MIN_PROGRESS_DELTA
                updates[:progress] = normalized
                @last_progress = normalized
              end
            end

            @menu_state_writer.set_loading_state(**updates) unless updates.empty?
            !updates.empty?
          end

          def clear
            @last_message = nil
            @last_progress = nil
            @menu_state_writer.set_loading_state(
              active: false,
              path: nil,
              progress: nil,
              index: nil,
              mode: nil,
              message: nil
            )
          end
        end
      end
    end
  end
end
