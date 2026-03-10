# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          class Overlay
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              open_toc_sidebar
              open_bookmarks_sidebar
              open_annotations_sidebar
              open_annotations_overlay
              open_help_overlay
              close_help_overlay
              toggle_view_mode
              toggle_page_numbering_mode
              increase_line_spacing
              decrease_line_spacing
              toggle_sidebar
              sidebar_move_up
              sidebar_move_down
              sidebar_activate
              popup_move_up
              popup_move_down
              popup_confirm
              popup_cancel
            ].freeze

            def initialize(reader_display_control:, reader_popup_control:)
              @reader_display_control = reader_display_control
              @reader_popup_control = reader_popup_control
            end

            def call(intent, payload = nil)
              case intent
              when :open_toc_sidebar
                validate_payload!(intent, payload)
                @reader_display_control.show_toc_sidebar
              when :open_bookmarks_sidebar
                validate_payload!(intent, payload)
                @reader_display_control.show_bookmarks_sidebar
              when :open_annotations_sidebar
                validate_payload!(intent, payload)
                @reader_display_control.show_annotations_sidebar
              when :open_annotations_overlay
                validate_payload!(intent, payload)
                @reader_display_control.show_annotations_overlay
              when :open_help_overlay
                validate_payload!(intent, payload)
                @reader_display_control.show_help_overlay
              when :close_help_overlay
                validate_payload!(intent, payload)
                @reader_display_control.hide_help_overlay
              when :toggle_view_mode
                validate_payload!(intent, payload)
                @reader_display_control.toggle_view_mode
              when :toggle_page_numbering_mode
                validate_payload!(intent, payload)
                @reader_display_control.toggle_page_numbering_mode
              when :increase_line_spacing
                validate_payload!(intent, payload)
                @reader_display_control.adjust_line_spacing(delta: 1)
              when :decrease_line_spacing
                validate_payload!(intent, payload)
                @reader_display_control.adjust_line_spacing(delta: -1)
              when :toggle_sidebar
                validate_payload!(intent, payload)
                @reader_display_control.toggle_sidebar_visibility
              when :sidebar_move_up
                @reader_display_control.move_sidebar_selection(delta: positive_delta(payload, intent))
              when :sidebar_move_down
                @reader_display_control.move_sidebar_selection(delta: positive_delta(payload, intent))
              when :sidebar_activate
                validate_payload!(intent, payload)
                @reader_display_control.activate_sidebar_selection
              when :popup_move_up
                @reader_popup_control.move_popup_selection(delta: positive_delta(payload, intent))
              when :popup_move_down
                @reader_popup_control.move_popup_selection(delta: positive_delta(payload, intent))
              when :popup_confirm
                validate_payload!(intent, payload)
                @reader_popup_control.confirm_popup
              when :popup_cancel
                validate_payload!(intent, payload)
                @reader_popup_control.cancel_popup
              else
                raise ArgumentError, "unsupported reader overlay intent: #{intent}"
              end

              :handled
            end

            private

            def supported_payloads
              {
                open_toc_sidebar: [NilClass],
                open_bookmarks_sidebar: [NilClass],
                open_annotations_sidebar: [NilClass],
                open_annotations_overlay: [NilClass],
                open_help_overlay: [NilClass],
                close_help_overlay: [NilClass],
                toggle_view_mode: [NilClass],
                toggle_page_numbering_mode: [NilClass],
                increase_line_spacing: [NilClass],
                decrease_line_spacing: [NilClass],
                toggle_sidebar: [NilClass],
                sidebar_move_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                sidebar_move_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                sidebar_activate: [NilClass],
                popup_move_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                popup_move_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                popup_confirm: [NilClass],
                popup_cancel: [NilClass],
              }
            end
          end
        end
      end
    end
  end
end
