# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Handles reader overlay, sidebar, and popup interaction intents.
          class Overlay
            include Shoko::Application::UseCases::Support::IntentActionGroup

            DISPLAY_INTENTS = %i[
              open_toc_sidebar
              open_bookmarks_sidebar
              open_annotations_sidebar
              open_annotations_overlay
              open_help_overlay
              close_help_overlay
              toggle_view_mode
              toggle_page_numbering_mode
              toggle_sidebar
            ].freeze
            LINE_SPACING_INTENTS = { increase_line_spacing: 1, decrease_line_spacing: -1 }.freeze
            SIDEBAR_MOVE_INTENTS = %i[sidebar_move_up sidebar_move_down].freeze
            POPUP_MOVE_INTENTS = %i[popup_move_up popup_move_down].freeze
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

            LINE_SPACING_MODES = %i[compact normal relaxed].freeze

            def initialize(reader_overlay_control:, reader_popup_control:,
                           reader_view_mutator:, app_config_store:, notification_writer:)
              @reader_overlay_control = reader_overlay_control
              @reader_popup_control = reader_popup_control
              @reader_view_mutator = reader_view_mutator
              @app_config_store = app_config_store
              @notification_writer = notification_writer
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader overlay intent')
            end

            private

            def routes
              @routes ||= display_routes.merge(line_spacing_routes).merge(sidebar_routes).merge(popup_routes).freeze
            end

            def supported_payloads
              nil_payloads(
                *DISPLAY_INTENTS,
                *LINE_SPACING_INTENTS.keys,
                :sidebar_activate,
                :popup_confirm,
                :popup_cancel
              ).merge(
                delta_payloads(*SIDEBAR_MOVE_INTENTS, *POPUP_MOVE_INTENTS)
              )
            end

            def display_routes
              {
                open_toc_sidebar: route(result: :handled) { @reader_overlay_control.show_toc_sidebar },
                open_bookmarks_sidebar: route(result: :handled) { @reader_overlay_control.show_bookmarks_sidebar },
                open_annotations_sidebar: route(result: :handled) { @reader_overlay_control.show_annotations_sidebar },
                open_annotations_overlay: route(result: :handled) { @reader_overlay_control.show_annotations_overlay },
                open_help_overlay: route(result: :handled) { @reader_view_mutator.update_reader(mode: :help) },
                close_help_overlay: route(result: :handled) { @reader_view_mutator.update_reader(mode: :read) },
                toggle_view_mode: route(result: :handled) { @reader_view_mutator.toggle_view_mode },
                toggle_page_numbering_mode: route(result: :handled) { toggle_page_numbering_mode },
                toggle_sidebar: route(result: :handled) { @reader_overlay_control.toggle_sidebar_visibility },
              }
            end

            def line_spacing_routes
              self.class::LINE_SPACING_INTENTS.transform_values do |delta|
                route(result: :handled) { adjust_line_spacing(delta) }
              end
            end

            def toggle_page_numbering_mode
              current_mode = @app_config_store.load.page_numbering_mode
              new_mode = current_mode == :absolute ? :dynamic : :absolute
              @reader_view_mutator.update_config(page_numbering_mode: new_mode)
              @notification_writer&.show_message("Page numbering: #{new_mode}")
            end

            def adjust_line_spacing(delta)
              current = LINE_SPACING_MODES.index(@app_config_store.load.line_spacing) || 1
              target = current + delta
              return unless target.between?(0, LINE_SPACING_MODES.length - 1)

              @reader_view_mutator.update_config(line_spacing: LINE_SPACING_MODES[target])
              @reader_view_mutator.update_reader(last_width: 0)
            end

            def sidebar_routes
              handled_routes(*SIDEBAR_MOVE_INTENTS, payload: :delta) do |delta|
                @reader_overlay_control.move_sidebar_selection(delta: delta)
              end.merge(
                sidebar_activate: route(result: :handled) { @reader_overlay_control.activate_sidebar_selection }
              )
            end

            def popup_routes
              handled_routes(*POPUP_MOVE_INTENTS, payload: :delta) do |delta|
                @reader_popup_control.move_popup_selection(delta: delta)
              end.merge(
                popup_confirm: route(result: :handled) { @reader_popup_control.confirm_popup },
                popup_cancel: route(result: :handled) { @reader_popup_control.cancel_popup }
              )
            end
          end
        end
      end
    end
  end
end
