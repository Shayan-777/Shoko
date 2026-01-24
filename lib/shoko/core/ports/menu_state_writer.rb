# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for writing menu state changes.
      # Adapters implementing this interface handle menu state updates without
      # coupling adapters to application-layer actions or state management.
      #
      # @example Implementing this port
      #   class MenuStateWriterAdapter
      #     include Shoko::Core::Ports::MenuStateWriter
      #
      #     def initialize(state)
      #       @state = state
      #     end
      #
      #     def update_menu(attrs)
      #       @state.dispatch(UpdateMenuAction.new(**attrs))
      #     end
      #   end
      module MenuStateWriter
        # Update multiple menu state attributes at once
        #
        # @param attrs [Hash] Menu attributes to update
        # @return [void]
        def update_menu(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_menu"
        end

        # Update the selected menu item
        #
        # @param value [Integer] Selected item index
        # @return [void]
        def update_selected(value)
          raise NotImplementedError, "#{self.class} must implement #update_selected"
        end

        # Update the browse selected item
        #
        # @param value [Integer] Browse selected index
        # @return [void]
        def update_browse_selected(value)
          raise NotImplementedError, "#{self.class} must implement #update_browse_selected"
        end

        # Update the menu mode
        #
        # @param mode [Symbol] Menu mode (:main, :browse, :search, :settings, :download, :dictionary, :annotations)
        # @return [void]
        def update_mode(mode)
          raise NotImplementedError, "#{self.class} must implement #update_mode"
        end

        # Update search state
        #
        # @param query [String, nil] Search query
        # @param cursor [Integer, nil] Cursor position
        # @param active [Boolean, nil] Whether search is active
        # @return [void]
        def update_search(query: nil, cursor: nil, active: nil)
          raise NotImplementedError, "#{self.class} must implement #update_search"
        end

        # Update settings selected item
        #
        # @param value [Integer] Settings selected index
        # @return [void]
        def update_settings_selected(value)
          raise NotImplementedError, "#{self.class} must implement #update_settings_selected"
        end

        # Update download state
        #
        # @param query [String, nil] Download query
        # @param cursor [Integer, nil] Cursor position
        # @param selected [Integer, nil] Selected item index
        # @param status [Symbol, nil] Download status
        # @param progress [Float, nil] Progress percentage
        # @return [void]
        def update_download(query: nil, cursor: nil, selected: nil, status: nil, progress: nil)
          raise NotImplementedError, "#{self.class} must implement #update_download"
        end

        # Update dictionary state
        #
        # @param query [String, nil] Dictionary query
        # @param cursor [Integer, nil] Cursor position
        # @param selected [Integer, nil] Selected item index
        # @param status [Symbol, nil] Dictionary status
        # @param progress [Float, nil] Progress percentage
        # @return [void]
        def update_dictionary(query: nil, cursor: nil, selected: nil, status: nil, progress: nil)
          raise NotImplementedError, "#{self.class} must implement #update_dictionary"
        end

        # Update annotation edit state
        #
        # @param text [String, nil] Edit text
        # @param cursor [Integer, nil] Cursor position
        # @return [void]
        def update_annotation_edit(text: nil, cursor: nil)
          raise NotImplementedError, "#{self.class} must implement #update_annotation_edit"
        end

        # Update selected annotation
        #
        # @param annotation [Hash, nil] Selected annotation data
        # @param book_path [String, nil] Book path of selected annotation
        # @return [void]
        def update_selected_annotation(annotation: nil, book_path: nil)
          raise NotImplementedError, "#{self.class} must implement #update_selected_annotation"
        end

        # Update all annotations mapping
        #
        # @param annotations [Hash] Mapping of book paths to annotations
        # @return [void]
        def update_annotations_all(annotations)
          raise NotImplementedError, "#{self.class} must implement #update_annotations_all"
        end

        # Update loading state
        #
        # @param path [String, nil] Path being loaded
        # @param active [Boolean, nil] Whether loading is active
        # @param progress [Float, nil] Progress percentage
        # @param message [String, nil] Loading message
        # @return [void]
        def update_loading(path: nil, active: nil, progress: nil, message: nil)
          raise NotImplementedError, "#{self.class} must implement #update_loading"
        end
      end
    end
  end
end
