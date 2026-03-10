# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_session_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local write surface for menu snapshot updates.
        class MenuSessionMutator
          def initialize(menu_session_store:)
            unless menu_session_store.is_a?(Shoko::Core::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore'
            end

            @menu_session_store = menu_session_store
          end

          def update_menu(attributes)
            persist(**attributes)
          end

          def update_selected(value)
            persist(selected: value)
          end

          def update_browse_selected(value)
            persist(browse_selected: value)
          end

          def update_mode(mode)
            persist(mode: mode)
          end

          def update_search(query: nil, cursor: nil, active: nil)
            attrs = {}
            attrs[:search_query] = query unless query.nil?
            attrs[:search_cursor] = cursor unless cursor.nil?
            attrs[:search_active] = active unless active.nil?
            persist(**attrs)
          end

          def update_settings_selected(value)
            persist(settings_selected: value)
          end

          def update_download(query: nil, cursor: nil, selected: nil, status: nil, progress: nil)
            attrs = {}
            attrs[:download_query] = query unless query.nil?
            attrs[:download_cursor] = cursor unless cursor.nil?
            attrs[:download_selected] = selected unless selected.nil?
            attrs[:download_status] = status unless status.nil?
            attrs[:download_progress] = progress unless progress.nil?
            persist(**attrs)
          end

          def update_dictionary(query: nil, cursor: nil, selected: nil, status: nil, progress: nil)
            attrs = {}
            attrs[:dictionary_query] = query unless query.nil?
            attrs[:dictionary_cursor] = cursor unless cursor.nil?
            attrs[:dictionary_selected] = selected unless selected.nil?
            attrs[:dictionary_status] = status unless status.nil?
            attrs[:dictionary_progress] = progress unless progress.nil?
            persist(**attrs)
          end

          def update_annotation_edit(text: nil, cursor: nil)
            attrs = {}
            attrs[:annotation_edit_text] = text unless text.nil?
            attrs[:annotation_edit_cursor] = cursor unless cursor.nil?
            persist(**attrs)
          end

          def update_selected_annotation(annotation: nil, book_path: nil)
            attrs = {}
            attrs[:selected_annotation] = annotation unless annotation.nil?
            attrs[:selected_annotation_book] = book_path unless book_path.nil?
            persist(**attrs)
          end

          def update_annotations_all(annotations)
            persist(annotations_all: annotations)
          end

          def update_loading(path: nil, active: nil, progress: nil, message: nil, index: nil, mode: nil)
            attrs = {}
            attrs[:loading_path] = path unless path.nil?
            attrs[:loading_active] = active unless active.nil?
            attrs[:loading_progress] = progress unless progress.nil?
            attrs[:loading_message] = message unless message.nil?
            attrs[:loading_index] = index unless index.nil?
            attrs[:loading_mode] = mode unless mode.nil?
            persist(**attrs)
          end

          def set_download_state(attrs)
            update_menu(attrs)
          end

          def set_dictionary_state(attrs)
            update_menu(attrs)
          end

          def set_annotation_state(attrs)
            update_menu(attrs)
          end

          def set_loading_state(path: nil, active: nil, progress: nil, message: nil, index: nil, mode: nil)
            update_loading(path: path, active: active, progress: progress, message: message, index: index, mode: mode)
          end

          private

          def persist(**attributes)
            return if attributes.empty?

            snapshot = @menu_session_store.load
            @menu_session_store.save(snapshot.with(**attributes))
          end
        end
      end
    end
  end
end
