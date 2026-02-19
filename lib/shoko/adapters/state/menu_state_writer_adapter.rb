# frozen_string_literal: true

require_relative '../../core/ports/menu_state_writer'
require_relative '../../application/ports/menu_state_writer'
require_relative 'actions/update_menu_action'

module Shoko
  module Adapters::State
    # Application adapter implementing the MenuStateWriter port.
    # Dispatches UpdateMenuAction to update menu state.
    class MenuStateWriterAdapter
      include Core::Ports::MenuStateWriter
      include Application::Ports::MenuStateWriter

      def initialize(state)
        @state = state
      end

      # Update multiple menu state attributes at once
      # @param attrs [Hash] Menu attributes to update
      def update_menu(attrs)
        @state.dispatch(Actions::UpdateMenuAction.new(**attrs))
      end

      # Update the selected menu item
      # @param value [Integer] Selected item index
      def update_selected(value)
        @state.dispatch(Actions::UpdateMenuAction.new(selected: value))
      end

      # Update the browse selected item
      # @param value [Integer] Browse selected index
      def update_browse_selected(value)
        @state.dispatch(Actions::UpdateMenuAction.new(browse_selected: value))
      end

      # Update the menu mode
      # @param mode [Symbol] Menu mode
      def update_mode(mode)
        @state.dispatch(Actions::UpdateMenuAction.new(mode: mode))
      end

      # Update search state
      # @param query [String, nil] Search query
      # @param cursor [Integer, nil] Cursor position
      # @param active [Boolean, nil] Whether search is active
      def update_search(query: nil, cursor: nil, active: nil)
        attrs = {}
        attrs[:search_query] = query unless query.nil?
        attrs[:search_cursor] = cursor unless cursor.nil?
        attrs[:search_active] = active unless active.nil?
        @state.dispatch(Actions::UpdateMenuAction.new(**attrs)) unless attrs.empty?
      end

      # Update settings selected item
      # @param value [Integer] Settings selected index
      def update_settings_selected(value)
        @state.dispatch(Actions::UpdateMenuAction.new(settings_selected: value))
      end

      # Update download state
      # @param query [String, nil] Download query
      # @param cursor [Integer, nil] Cursor position
      # @param selected [Integer, nil] Selected item index
      # @param status [Symbol, nil] Download status
      # @param progress [Float, nil] Progress percentage
      def update_download(query: nil, cursor: nil, selected: nil, status: nil, progress: nil)
        attrs = {}
        attrs[:download_query] = query unless query.nil?
        attrs[:download_cursor] = cursor unless cursor.nil?
        attrs[:download_selected] = selected unless selected.nil?
        attrs[:download_status] = status unless status.nil?
        attrs[:download_progress] = progress unless progress.nil?
        @state.dispatch(Actions::UpdateMenuAction.new(**attrs)) unless attrs.empty?
      end

      # Update dictionary state
      # @param query [String, nil] Dictionary query
      # @param cursor [Integer, nil] Cursor position
      # @param selected [Integer, nil] Selected item index
      # @param status [Symbol, nil] Dictionary status
      # @param progress [Float, nil] Progress percentage
      def update_dictionary(query: nil, cursor: nil, selected: nil, status: nil, progress: nil)
        attrs = {}
        attrs[:dictionary_query] = query unless query.nil?
        attrs[:dictionary_cursor] = cursor unless cursor.nil?
        attrs[:dictionary_selected] = selected unless selected.nil?
        attrs[:dictionary_status] = status unless status.nil?
        attrs[:dictionary_progress] = progress unless progress.nil?
        @state.dispatch(Actions::UpdateMenuAction.new(**attrs)) unless attrs.empty?
      end

      # Update annotation edit state
      # @param text [String, nil] Edit text
      # @param cursor [Integer, nil] Cursor position
      def update_annotation_edit(text: nil, cursor: nil)
        attrs = {}
        attrs[:annotation_edit_text] = text unless text.nil?
        attrs[:annotation_edit_cursor] = cursor unless cursor.nil?
        @state.dispatch(Actions::UpdateMenuAction.new(**attrs)) unless attrs.empty?
      end

      # Update selected annotation
      # @param annotation [Hash, nil] Selected annotation data
      # @param book_path [String, nil] Book path of selected annotation
      def update_selected_annotation(annotation: nil, book_path: nil)
        attrs = {}
        attrs[:selected_annotation] = annotation unless annotation.nil?
        attrs[:selected_annotation_book] = book_path unless book_path.nil?
        @state.dispatch(Actions::UpdateMenuAction.new(**attrs)) unless attrs.empty?
      end

      # Update all annotations mapping
      # @param annotations [Hash] Mapping of book paths to annotations
      def update_annotations_all(annotations)
        @state.dispatch(Actions::UpdateMenuAction.new(annotations_all: annotations))
      end

      # Update loading state
      # @param path [String, nil] Path being loaded
      # @param active [Boolean, nil] Whether loading is active
      # @param progress [Float, nil] Progress percentage
      # @param message [String, nil] Loading message
      # @param index [Integer, nil] Loading index
      # @param mode [Symbol, nil] Loading mode
      def update_loading(path: nil, active: nil, progress: nil, message: nil, index: nil, mode: nil)
        attrs = {}
        attrs[:loading_path] = path unless path.nil?
        attrs[:loading_active] = active unless active.nil?
        attrs[:loading_progress] = progress unless progress.nil?
        attrs[:loading_message] = message unless message.nil?
        attrs[:loading_index] = index unless index.nil?
        attrs[:loading_mode] = mode unless mode.nil?
        @state.dispatch(Actions::UpdateMenuAction.new(**attrs)) unless attrs.empty?
      end
    end
  end
end
