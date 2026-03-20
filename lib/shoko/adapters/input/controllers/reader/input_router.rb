# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Routes input to the correct subsystem based on current reader overlays/modes.
          class InputRouter
            def initialize(reader_state_reader:, input_controller:, ui_controller:, key_classifier: nil)
              @reader_state_reader = reader_state_reader
              @input_controller = input_controller
              @ui_controller = ui_controller
              @key_classifier = key_classifier
            end

            def dispatch_input_keys(keys)
              return @input_controller.handle_annotations_overlay_input(keys) if annotation_overlay_input?(keys)
              return @ui_controller.close_dictionary if dictionary_cancel?(keys)
              return @ui_controller.close_in_book_search if in_book_search_cancel?(keys)
              return @input_controller.handle_popup_menu_input(keys) if popup_menu_visible?

              keys.each { |key| @input_controller.handle_key(key) }
            end

            def annotation_editor_active?
              annotation_editor_visible?
            end

            private

            def annotations_overlay_active?
              @ui_controller.annotations_overlay_visible?
            end

            def annotation_editor_visible?
              @ui_controller.annotation_editor_visible?
            end

            def popup_menu_visible?
              popup_menu = @reader_state_reader.popup_menu
              popup_menu&.visible
            end

            def dictionary_visible?
              @ui_controller.dictionary_visible?
            end

            def in_book_search_visible?
              @ui_controller.in_book_search_visible?
            end

            def cancel_key_pressed?(keys)
              return false unless @key_classifier

              Array(keys).any? { |key| @key_classifier.cancel_key?(key) }
            end

            def annotation_overlay_input?(_keys)
              annotations_overlay_active? && !annotation_editor_visible?
            end

            def dictionary_cancel?(keys)
              dictionary_visible? && cancel_key_pressed?(keys)
            end

            def in_book_search_cancel?(keys)
              in_book_search_visible? && cancel_key_pressed?(keys)
            end
          end
        end
      end
    end
  end
end
