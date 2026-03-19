# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module SelectionMouseHandlerSupport
          # Exposes optional selection handler dependencies without hard-coding a constructor.
          module DependencyAccess
            private

            # Host class provides these dependencies as instance variables.
            # Each method returns the corresponding dependency or nil.
            def smh_selection_service
              defined?(@selection_service) ? @selection_service : nil
            end

            def smh_rendered_content_reader
              defined?(@rendered_content_reader) ? @rendered_content_reader : nil
            end

            def smh_render_registry
              defined?(@render_registry) ? @render_registry : nil
            end

            def smh_ui_controller
              defined?(@ui_controller_ref) ? @ui_controller_ref : nil
            end

            def smh_clipboard_service
              defined?(@clipboard_service) ? @clipboard_service : nil
            end

            def smh_dictionary_availability
              defined?(@dictionary_availability) ? @dictionary_availability : nil
            end

            def smh_ui_component_factory
              defined?(@ui_component_factory) ? @ui_component_factory : nil
            end
          end
        end
      end
    end
  end
end
