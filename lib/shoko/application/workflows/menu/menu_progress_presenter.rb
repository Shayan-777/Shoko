# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_session_store'

module Shoko
  module Application
    module Workflows
      module Menu
        # Encapsulates loading-state updates while a book is preprocessed.
        class MenuProgressPresenter
          MIN_PROGRESS_DELTA = 0.01

          def initialize(menu_session_store)
            unless menu_session_store.is_a?(Shoko::Core::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore'
            end

            @menu_session_store = menu_session_store
            @last_message = nil
            @last_progress = nil
          end

          def show(path:, index:, mode:)
            @last_message = 'Preparing book...'
            @last_progress = 0.0
            persist_loading_state(
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

            persist_loading_state(**updates) unless updates.empty?
            !updates.empty?
          end

          def clear
            @last_message = nil
            @last_progress = nil
            persist_loading_state(
              active: false,
              path: nil,
              progress: nil,
              index: nil,
              mode: nil,
              message: nil
            )
          end

          private

          def persist_loading_state(**updates)
            menu = current_menu
            @menu_session_store.save(menu.with(
                                       loading_active: updates.fetch(:active, menu.loading_active),
                                       loading_path: updates.fetch(:path, menu.loading_path),
                                       loading_progress: updates.fetch(:progress, menu.loading_progress),
                                       loading_message: updates.fetch(:message, menu.loading_message),
                                       loading_index: updates.fetch(:index, menu.loading_index),
                                       loading_mode: updates.fetch(:mode, menu.loading_mode)
                                     ))
          end

          def current_menu
            @menu_session_store.load
          end
        end
      end
    end
  end
end
