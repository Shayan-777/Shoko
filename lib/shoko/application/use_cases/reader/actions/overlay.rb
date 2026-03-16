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
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader overlay intent')
            end

            private

            def routes
              @routes ||= {
                open_toc_sidebar: route(result: :handled) { @reader_display_control.show_toc_sidebar },
                open_bookmarks_sidebar: route(result: :handled) { @reader_display_control.show_bookmarks_sidebar },
                open_annotations_sidebar: route(result: :handled) { @reader_display_control.show_annotations_sidebar },
                open_annotations_overlay: route(result: :handled) { @reader_display_control.show_annotations_overlay },
                open_help_overlay: route(result: :handled) { @reader_display_control.show_help_overlay },
                close_help_overlay: route(result: :handled) { @reader_display_control.hide_help_overlay },
                toggle_view_mode: route(result: :handled) { @reader_display_control.toggle_view_mode },
                toggle_page_numbering_mode: route(result: :handled) { @reader_display_control.toggle_page_numbering_mode },
                increase_line_spacing: route(result: :handled) { @reader_display_control.adjust_line_spacing(delta: 1) },
                decrease_line_spacing: route(result: :handled) { @reader_display_control.adjust_line_spacing(delta: -1) },
                toggle_sidebar: route(result: :handled) { @reader_display_control.toggle_sidebar_visibility },
                sidebar_move_up: route(payload: :delta, result: :handled) do |delta|
                  @reader_display_control.move_sidebar_selection(delta: delta)
                end,
                sidebar_move_down: route(payload: :delta, result: :handled) do |delta|
                  @reader_display_control.move_sidebar_selection(delta: delta)
                end,
                sidebar_activate: route(result: :handled) { @reader_display_control.activate_sidebar_selection },
                popup_move_up: route(payload: :delta, result: :handled) do |delta|
                  @reader_popup_control.move_popup_selection(delta: delta)
                end,
                popup_move_down: route(payload: :delta, result: :handled) do |delta|
                  @reader_popup_control.move_popup_selection(delta: delta)
                end,
                popup_confirm: route(result: :handled) { @reader_popup_control.confirm_popup },
                popup_cancel: route(result: :handled) { @reader_popup_control.cancel_popup },
              }.freeze
            end

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
