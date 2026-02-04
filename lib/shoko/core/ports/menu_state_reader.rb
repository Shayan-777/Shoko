# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for reading menu state.
      # Adapters implementing this interface provide access to menu/navigation state
      # without coupling adapters to application-layer selectors or state management.
      #
      # @example Implementing this port
      #   class MenuStateReaderAdapter
      #     include Shoko::Core::Ports::MenuStateReader
      #
      #     def initialize(state)
      #       @state = state
      #     end
      #
      #     def selected
      #       MenuSelectors.selected(@state)
      #     end
      #   end
      module MenuStateReader
        # Get the currently selected menu item index
        #
        # @return [Integer, nil] Selected item index
        def selected
          raise NotImplementedError, "#{self.class} must implement #selected"
        end

        # Get the current menu mode
        #
        # @return [Symbol, nil] Menu mode (:main, :browse, :search, :settings, :download, :dictionary, :annotations)
        def mode
          raise NotImplementedError, "#{self.class} must implement #mode"
        end

        # Get the selected item in browse view
        #
        # @return [Integer, nil] Browse selected index
        def browse_selected
          raise NotImplementedError, "#{self.class} must implement #browse_selected"
        end

        # Get the current search query
        #
        # @return [String] Search query text
        def search_query
          raise NotImplementedError, "#{self.class} must implement #search_query"
        end

        # Get the search input cursor position
        #
        # @return [Integer, nil] Cursor position
        def search_cursor
          raise NotImplementedError, "#{self.class} must implement #search_cursor"
        end

        # Check if search is currently active
        #
        # @return [Boolean] True if search is active
        def search_active?
          raise NotImplementedError, "#{self.class} must implement #search_active?"
        end

        # Get the selected settings item index
        #
        # @return [Integer, nil] Settings selected index
        def settings_selected
          raise NotImplementedError, "#{self.class} must implement #settings_selected"
        end

        # Check if wipe cache cached data option is enabled
        #
        # @return [Boolean]
        def wipe_cache_cached?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_cached?"
        end

        # Check if wipe cache downloads option is enabled
        #
        # @return [Boolean]
        def wipe_cache_downloads?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_downloads?"
        end

        # Check if wipe cache nuke option is enabled
        #
        # @return [Boolean]
        def wipe_cache_nuke?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_nuke?"
        end

        # Check if wipe cache annotations option is enabled
        #
        # @return [Boolean]
        def wipe_cache_annotations?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_annotations?"
        end

        # Check if wipe cache bookmarks option is enabled
        #
        # @return [Boolean]
        def wipe_cache_bookmarks?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_bookmarks?"
        end

        # Check if wipe cache config option is enabled
        #
        # @return [Boolean]
        def wipe_cache_config?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_config?"
        end

        # Check if wipe cache progress option is enabled
        #
        # @return [Boolean]
        def wipe_cache_progress?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_progress?"
        end

        # Get the current download query
        #
        # @return [String] Download query text
        def download_query
          raise NotImplementedError, "#{self.class} must implement #download_query"
        end

        # Get the download input cursor position
        #
        # @return [Integer, nil] Cursor position
        def download_cursor
          raise NotImplementedError, "#{self.class} must implement #download_cursor"
        end

        # Get the selected download item index
        #
        # @return [Integer, nil] Download selected index
        def download_selected
          raise NotImplementedError, "#{self.class} must implement #download_selected"
        end

        # Get the download status
        #
        # @return [Symbol, nil] Download status
        def download_status
          raise NotImplementedError, "#{self.class} must implement #download_status"
        end

        # Get the download progress
        #
        # @return [Float, nil] Progress percentage (0.0-1.0)
        def download_progress
          raise NotImplementedError, "#{self.class} must implement #download_progress"
        end

        # Get the current dictionary query
        #
        # @return [String] Dictionary query text
        def dictionary_query
          raise NotImplementedError, "#{self.class} must implement #dictionary_query"
        end

        # Get the dictionary input cursor position
        #
        # @return [Integer, nil] Cursor position
        def dictionary_cursor
          raise NotImplementedError, "#{self.class} must implement #dictionary_cursor"
        end

        # Get the selected dictionary item index
        #
        # @return [Integer, nil] Dictionary selected index
        def dictionary_selected
          raise NotImplementedError, "#{self.class} must implement #dictionary_selected"
        end

        # Get the dictionary status
        #
        # @return [Symbol, nil] Dictionary status
        def dictionary_status
          raise NotImplementedError, "#{self.class} must implement #dictionary_status"
        end

        # Get the dictionary progress
        #
        # @return [Float, nil] Progress percentage (0.0-1.0)
        def dictionary_progress
          raise NotImplementedError, "#{self.class} must implement #dictionary_progress"
        end

        # Get all annotations mapping
        #
        # @return [Hash] Mapping of book paths to annotations
        def annotations_all
          raise NotImplementedError, "#{self.class} must implement #annotations_all"
        end

        # Get the currently selected annotation
        #
        # @return [Hash, nil] Selected annotation data
        def selected_annotation
          raise NotImplementedError, "#{self.class} must implement #selected_annotation"
        end

        # Get the book path of the selected annotation
        #
        # @return [String, nil] Book path
        def selected_annotation_book
          raise NotImplementedError, "#{self.class} must implement #selected_annotation_book"
        end

        # Get the annotation edit text
        #
        # @return [String] Edit text
        def annotation_edit_text
          raise NotImplementedError, "#{self.class} must implement #annotation_edit_text"
        end

        # Get the annotation edit cursor position
        #
        # @return [Integer, nil] Cursor position
        def annotation_edit_cursor
          raise NotImplementedError, "#{self.class} must implement #annotation_edit_cursor"
        end

        # Get the loading path
        #
        # @return [String, nil] Path being loaded
        def loading_path
          raise NotImplementedError, "#{self.class} must implement #loading_path"
        end

        # Check if loading is active
        #
        # @return [Boolean] True if loading
        def loading_active?
          raise NotImplementedError, "#{self.class} must implement #loading_active?"
        end

        # Get the loading progress
        #
        # @return [Float, nil] Progress percentage (0.0-1.0)
        def loading_progress
          raise NotImplementedError, "#{self.class} must implement #loading_progress"
        end

        # Get the loading message
        #
        # @return [String, nil] Loading message
        def loading_message
          raise NotImplementedError, "#{self.class} must implement #loading_message"
        end

        # Get the download search results
        #
        # @return [Array] Download results list
        def download_results
          raise NotImplementedError, "#{self.class} must implement #download_results"
        end

        # Get the download status message
        #
        # @return [String, nil] Status message
        def download_message
          raise NotImplementedError, "#{self.class} must implement #download_message"
        end

        # Get the download count (total results)
        #
        # @return [Integer] Result count
        def download_count
          raise NotImplementedError, "#{self.class} must implement #download_count"
        end

        # Get the dictionary search results
        #
        # @return [Array] Dictionary results list
        def dictionary_results
          raise NotImplementedError, "#{self.class} must implement #dictionary_results"
        end

        # Get the dictionary status message
        #
        # @return [String, nil] Status message
        def dictionary_message
          raise NotImplementedError, "#{self.class} must implement #dictionary_message"
        end
      end
    end
  end
end
