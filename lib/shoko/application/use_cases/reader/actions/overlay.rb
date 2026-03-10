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

            def initialize(reader_runtime:)
              @reader_runtime = reader_runtime
            end

            def call(intent, payload = nil)
              case intent
              when :open_toc_sidebar
                validate_payload!(intent, payload)
                @reader_runtime.open_toc_sidebar
              when :open_bookmarks_sidebar
                validate_payload!(intent, payload)
                @reader_runtime.open_bookmarks_sidebar
              when :open_annotations_sidebar
                validate_payload!(intent, payload)
                @reader_runtime.open_annotations_sidebar
              when :open_annotations_overlay
                validate_payload!(intent, payload)
                @reader_runtime.open_annotations_overlay
              when :open_help_overlay
                validate_payload!(intent, payload)
                @reader_runtime.open_help_overlay
              when :close_help_overlay
                validate_payload!(intent, payload)
                @reader_runtime.close_help_overlay
              when :toggle_view_mode
                validate_payload!(intent, payload)
                @reader_runtime.toggle_view_mode
              when :toggle_page_numbering_mode
                validate_payload!(intent, payload)
                @reader_runtime.toggle_page_numbering_mode
              when :increase_line_spacing
                validate_payload!(intent, payload)
                @reader_runtime.increase_line_spacing
              when :decrease_line_spacing
                validate_payload!(intent, payload)
                @reader_runtime.decrease_line_spacing
              when :toggle_sidebar
                validate_payload!(intent, payload)
                @reader_runtime.toggle_sidebar
              when :sidebar_move_up
                @reader_runtime.sidebar_move(positive_delta(payload, intent))
              when :sidebar_move_down
                @reader_runtime.sidebar_move(positive_delta(payload, intent))
              when :sidebar_activate
                validate_payload!(intent, payload)
                @reader_runtime.sidebar_activate
              when :popup_move_up
                @reader_runtime.popup_move(positive_delta(payload, intent))
              when :popup_move_down
                @reader_runtime.popup_move(positive_delta(payload, intent))
              when :popup_confirm
                validate_payload!(intent, payload)
                @reader_runtime.popup_confirm
              when :popup_cancel
                validate_payload!(intent, payload)
                @reader_runtime.popup_cancel
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
