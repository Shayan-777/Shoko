# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_session_store'
require_relative '../../../core/ports/outbound/menu_transient_store'
require_relative '../../../core/models/session/menu_state_partition'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Encapsulates loading-state updates while a book is preprocessed.
        class MenuProgressPresenter
          MIN_PROGRESS_DELTA = 0.01

          def initialize(menu_session_store, menu_transient_store)
            unless menu_session_store.is_a?(Shoko::Core::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore'
            end
            unless menu_transient_store.is_a?(Shoko::Core::Ports::Outbound::MenuTransientStore)
              raise ArgumentError, 'menu_transient_store must implement Core::Ports::Outbound::MenuTransientStore'
            end

            @menu_session_store = menu_session_store
            @menu_transient_store = menu_transient_store
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

          def update_progress(progress)
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

            return if updates.empty?

            persist_loading_state(**updates)
          end

          def clear
            @last_message = nil
            @last_progress = nil
            persist_loading_state(active: false, path: nil, progress: nil, index: nil, mode: nil, message: nil)
          end

          private

          def persist_loading_state(**updates)
            payload = loading_state_payload(current_menu, updates)
            persist_partitioned_loading_state(payload)
          end

          def current_menu
            Shoko::Core::Models::Session::MenuSnapshot.build(
              @menu_session_store.load.to_h.merge(@menu_transient_store.load.to_h)
            )
          end

          def rollback_loading_state(previous_session, previous_transient, session_attributes, transient_attributes)
            @menu_session_store.save(previous_session) if previous_session && session_attributes&.any?
            return unless previous_transient && transient_attributes && !transient_attributes.empty?

            @menu_transient_store.save(previous_transient)
          rescue Shoko::Error, ArgumentError => e
            @last_loading_state_rollback_error = e
          end

          def loading_state_payload(menu, updates)
            {
              loading_active: updates.fetch(:active, menu.loading_active),
              loading_path: updates.fetch(:path, menu.loading_path),
              loading_progress: updates.fetch(:progress, menu.loading_progress),
              loading_message: updates.fetch(:message, menu.loading_message),
              loading_index: updates.fetch(:index, menu.loading_index),
              loading_mode: updates.fetch(:mode, menu.loading_mode),
            }
          end

          def persist_partitioned_loading_state(payload)
            session_attributes, transient_attributes = Shoko::Core::Models::Session::MenuStatePartition.split(payload)
            previous_session = @menu_session_store.load
            previous_transient = @menu_transient_store.load

            save_partitioned_loading_state(
              previous_session: previous_session,
              previous_transient: previous_transient,
              session_attributes: session_attributes,
              transient_attributes: transient_attributes
            )
          rescue Shoko::Error, ArgumentError
            rollback_loading_state(previous_session, previous_transient, session_attributes, transient_attributes)
            raise
          end

          def save_partitioned_loading_state(previous_session:, previous_transient:, session_attributes:,
                                             transient_attributes:)
            @menu_session_store.save(previous_session.with(**session_attributes)) unless session_attributes.empty?
            return unless transient_attributes.any?

            @menu_transient_store.save(previous_transient.with(**transient_attributes))
          end
        end
      end
    end
  end
end
