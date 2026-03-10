# frozen_string_literal: true

require_relative '../../../core/models/session/menu_snapshot'
require_relative '../../../core/ports/outbound/menu_session_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local dynamic view over the current menu snapshot.
        class MenuSessionView
          Shoko::Core::Models::Session::MenuSnapshotFields.each do |field|
            define_method(field) do
              current_menu.to_h[field]
            end
          end

          def initialize(menu_session_store:)
            unless menu_session_store.is_a?(Shoko::Core::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore'
            end

            @menu_session_store = menu_session_store
          end

          def library_details_open?
            current_menu.library_details_open?
          end

          def search_active?
            current_menu.search_active?
          end

          def loading_active?
            current_menu.loading_active?
          end

          def wipe_cache_cached?
            value = current_menu.wipe_cache_cached
            value.nil? || value == true
          end

          def wipe_cache_downloads?
            current_menu.wipe_cache_downloads == true
          end

          def wipe_cache_nuke?
            current_menu.wipe_cache_nuke == true
          end

          def wipe_cache_annotations?
            current_menu.wipe_cache_annotations == true
          end

          def wipe_cache_bookmarks?
            current_menu.wipe_cache_bookmarks == true
          end

          def wipe_cache_config?
            current_menu.wipe_cache_config == true
          end

          def wipe_cache_progress?
            current_menu.wipe_cache_progress == true
          end

          def current_menu_mode
            current_menu.mode
          end

          def selected_library_index
            current_menu.browse_selected
          end

          def selected_annotation_record
            current_menu.selected_annotation
          end

          def selected_annotation_book_path
            current_menu.selected_annotation_book
          end

          def annotation_editor_text
            current_menu.annotation_edit_text
          end

          def dictionary_entries
            Array(current_menu.dictionary_results)
          end

          def snapshot
            current_menu
          end

          private

          def current_menu
            @menu_session_store.load
          end
        end
      end
    end
  end
end
