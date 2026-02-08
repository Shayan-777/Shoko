# frozen_string_literal: true

module Shoko
  module Application
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
            if annotations_overlay_active? && !annotation_editor_visible?
              @input_controller.handle_annotations_overlay_input(keys)
            elsif dictionary_visible? && cancel_key_pressed?(keys)
              @ui_controller.close_dictionary
            elsif popup_menu_visible?
              @input_controller.handle_popup_menu_input(keys)
            else
              keys.each { |key| @input_controller.handle_key(key) }
            end
          end

          def annotation_editor_active?
            editor_overlay = @reader_state_reader.annotation_editor_overlay
            editor_overlay.respond_to?(:visible?) && editor_overlay.visible?
          rescue StandardError
            false
          end

          private

          def annotations_overlay_active?
            overlay = @reader_state_reader.annotations_overlay
            overlay.respond_to?(:visible?) && overlay.visible?
          rescue StandardError
            false
          end

          def annotation_editor_visible?
            editor_overlay = @reader_state_reader.annotation_editor_overlay
            editor_overlay.respond_to?(:visible?) && editor_overlay.visible?
          rescue StandardError
            false
          end

          def popup_menu_visible?
            popup_menu = @reader_state_reader.popup_menu
            popup_menu&.visible
          rescue StandardError
            false
          end

          def dictionary_visible?
            panel = @reader_state_reader.dictionary_panel
            popup = @reader_state_reader.dictionary_popup
            panel_visible = panel.respond_to?(:visible?) && panel.visible?
            popup_visible = popup.respond_to?(:visible?) && popup.visible?
            panel_visible || popup_visible
          rescue StandardError
            false
          end

          def cancel_key_pressed?(keys)
            return false unless @key_classifier

            Array(keys).any? { |key| @key_classifier.cancel_key?(key) }
          end
        end
      end
    end
  end
end
