# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for reader display, overlay, and sidebar interaction.
        module ReaderDisplayControl
          def show_toc_sidebar
            raise NotImplementedError, "#{self.class} must implement #show_toc_sidebar"
          end

          def show_bookmarks_sidebar
            raise NotImplementedError, "#{self.class} must implement #show_bookmarks_sidebar"
          end

          def show_annotations_sidebar
            raise NotImplementedError, "#{self.class} must implement #show_annotations_sidebar"
          end

          def show_annotations_overlay
            raise NotImplementedError, "#{self.class} must implement #show_annotations_overlay"
          end

          def show_help_overlay
            raise NotImplementedError, "#{self.class} must implement #show_help_overlay"
          end

          def hide_help_overlay
            raise NotImplementedError, "#{self.class} must implement #hide_help_overlay"
          end

          def toggle_view_mode
            raise NotImplementedError, "#{self.class} must implement #toggle_view_mode"
          end

          def toggle_page_numbering_mode
            raise NotImplementedError, "#{self.class} must implement #toggle_page_numbering_mode"
          end

          def adjust_line_spacing(delta:)
            raise NotImplementedError, "#{self.class} must implement #adjust_line_spacing"
          end

          def toggle_sidebar_visibility
            raise NotImplementedError, "#{self.class} must implement #toggle_sidebar_visibility"
          end

          def move_sidebar_selection(delta:)
            raise NotImplementedError, "#{self.class} must implement #move_sidebar_selection"
          end

          def activate_sidebar_selection
            raise NotImplementedError, "#{self.class} must implement #activate_sidebar_selection"
          end
        end
      end
    end
  end
end
