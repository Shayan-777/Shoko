# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Focused writer for reader/menu state changes.
      module ReaderStateWriter
        def update_reader(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_reader"
        end

        def update_navigation(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_navigation"
        end

        def update_bookmarks(bookmarks)
          raise NotImplementedError, "#{self.class} must implement #update_bookmarks"
        end

        def update_sidebar(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_sidebar"
        end

        def update_config(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_config"
        end

        def clear_selection
          raise NotImplementedError, "#{self.class} must implement #clear_selection"
        end

        def quit_to_menu
          raise NotImplementedError, "#{self.class} must implement #quit_to_menu"
        end

        def update_reader_meta(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_reader_meta"
        end
      end
    end
  end
end
