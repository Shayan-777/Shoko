# frozen_string_literal: true

require 'shoko/shared/index_range'
require 'shoko/shared/hash_normalizer'
require 'shoko/shared/terminal/mouse_button'
require 'shoko/core/services/grapheme_cursor'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Handles translator-screen mouse selection and clipboard context-menu interactions.
          class TranslatorMouseHandler
            def initialize(
              menu_state_reader:,
              menu_session_mutator:,
              input_controller:,
              translator_screen:,
              clipboard_service: nil,
              notification_service: nil
            )
              @menu_state_reader = menu_state_reader
              @menu_session_mutator = menu_session_mutator
              @input_controller = input_controller
              @translator_screen = translator_screen
              @clipboard_service = clipboard_service
              @notification_service = notification_service
              @drag_origin = nil
            end

            def handle(event, bounds:)
              return false unless event
              return false unless @menu_state_reader.mode.to_sym == :translator

              if Shoko::Shared::Terminal::MouseButton.right_click_press?(event)
                return handle_context_click(event, bounds)
              end
              return dispatch_popup_event!(event, bounds) if context_menu_visible?
              return start_drag_interaction!(event, bounds) if left_button_press?(event)
              return update_drag_selection!(event, bounds) if left_drag?(event)
              return finish_drag_interaction(event, bounds) if left_button_release?(event)

              false
            end

            private

            def selection_contains_hit?(selection, hit)
              @translator_screen.selection_contains_hit?(selection, hit)
            end

            def source_selection?(selection)
              selection && selection[:pane].to_sym == :source
            end

            def current_source_cursor
              text = @menu_state_reader.translator_input_text.to_s
              Shoko::Core::Services::GraphemeCursor.clamp(text, @menu_state_reader.translator_input_cursor)
            end

            def translator_input_length
              @menu_state_reader.translator_input_text.to_s.length
            end

            def context_menu_visible?
              !current_context_menu.nil?
            end

            def current_selection
              normalize_hash(@menu_state_reader.translator_selection)
            end

            def current_context_menu
              normalize_hash(@menu_state_reader.translator_context_menu)
            end

            def normalize_hash(value)
              return nil unless value.is_a?(Hash)

              Shoko::Shared::HashNormalizer.symbolize_keys(value)
            end

            def body_hit_for(event, bounds)
              @translator_screen.body_hit(terminal_column(event), terminal_row(event), bounds)
            end

            def terminal_column(event)
              event[:x].to_i + 1
            end

            def terminal_row(event)
              event[:y].to_i + 1
            end

            def clear_context_menu!
              update_menu(translator_context_menu: nil)
              :cleared
            end

            def update_menu(payload)
              @menu_session_mutator.update_menu(payload)
            end

            def notify(message)
              @notification_service&.set_message(message.to_s.strip)
            end

            def left_button_press?(event)
              !event[:released] && event[:button].to_i.zero?
            end

            def left_button_release?(event)
              event[:released] && event[:button].to_i.zero?
            end

            def left_drag?(event)
              button = event[:button].to_i
              !event[:released] && button.anybits?(32) && button.nobits?(0b11)
            end

            def handle_context_click(event, bounds)
              hit = body_hit_for(event, bounds)
              return clear_context_menu! if hit.nil? && context_menu_visible?
              return false unless hit

              update_menu(context_menu_payload(hit, event))
              true
            end

            def dispatch_popup_event!(event, bounds)
              return :handled if left_button_press?(event)
              return false unless left_button_release?(event)

              action = @translator_screen.context_menu_hit(terminal_column(event), terminal_row(event), bounds)
              action ? perform_context_menu_action(action[:id]) : clear_context_menu!
              :handled
            end

            def start_drag_interaction!(event, bounds)
              hit = body_hit_for(event, bounds)
              return false unless hit

              @drag_origin = {
                column: terminal_column(event),
                row: terminal_row(event),
                hit: hit,
              }
              update_menu(translator_selection: nil, translator_context_menu: nil)
              :handled
            end

            def update_drag_selection!(event, bounds)
              return false unless @drag_origin

              hit = body_hit_for(event, bounds)
              return :handled unless same_drag_pane?(hit)

              update_menu(
                translator_selection: drag_selection(event, bounds),
                translator_context_menu: nil
              )
              :handled
            end

            def finish_drag_interaction(event, bounds)
              return false unless @drag_origin

              hit = drag_release_hit(event, bounds)
              selection = drag_release_selection(event, bounds, hit)
              finalize_drag(hit, selection)
              true
            ensure
              @drag_origin = nil
            end

            def context_menu_payload(hit, event)
              selection = preserved_context_selection(hit)
              paste_index, replace_selection = paste_target_for(hit, selection)
              {
                translator_selection: selection,
                translator_context_menu: {
                  pane: hit[:kind],
                  anchor_column: terminal_column(event),
                  anchor_row: terminal_row(event),
                  paste_index: paste_index,
                  replace_selection: replace_selection,
                },
              }
            end

            def preserved_context_selection(hit)
              selection = current_selection
              selection_contains_hit?(selection, hit) ? selection : nil
            end

            def same_drag_pane?(hit)
              hit && hit[:kind] == @drag_origin[:hit][:kind]
            end

            def drag_selection(event, bounds)
              @translator_screen.selection_from_points(
                start_column: @drag_origin[:column],
                start_row: @drag_origin[:row],
                end_column: terminal_column(event),
                end_row: terminal_row(event),
                bounds: bounds
              )
            end

            def drag_release_hit(event, bounds)
              body_hit_for(event, bounds) || @drag_origin[:hit]
            end

            def drag_release_selection(event, bounds, hit)
              selection = same_drag_pane?(hit) ? drag_selection(event, bounds) : nil
              preserve_existing_drag_selection(selection)
            end

            def preserve_existing_drag_selection(selection)
              return selection if selection

              current = current_selection
              return nil unless current && current[:pane].to_sym == @drag_origin[:hit][:kind]

              current
            end

            def finalize_drag(hit, selection)
              if selection
                update_menu(translator_selection: selection, translator_context_menu: nil)
              elsif hit[:kind] == :source
                focus_source_input(hit[:index])
              else
                update_menu(translator_selection: nil, translator_context_menu: nil)
              end
            end

            def perform_context_menu_action(action_id)
              case action_id
              when :copy_to_clipboard
                copy_selection_to_clipboard
              when :paste_from_clipboard
                paste_from_clipboard
              else
                clear_context_menu!
              end
            end

            def copy_selection_to_clipboard
              text = @translator_screen.selection_text(current_selection)
              return notify_and_dismiss('Nothing selected to copy') if text.empty?

              clip = @clipboard_service
              return notify_and_dismiss('Clipboard is unavailable') unless clip&.available?

              clip.copy_with_feedback(text) { |message| notify(message) }
              clear_context_menu!
            end

            def paste_from_clipboard
              clip = @clipboard_service
              return notify_and_dismiss('Clipboard is unavailable') unless clip&.read_available?

              pasted_text = clip.read_with_feedback { |message| notify(message) }
              return clear_context_menu! unless pasted_text

              replace_source_text(pasted_text)
            end

            def replace_source_text(pasted_text)
              current_text = @menu_state_reader.translator_input_text.to_s
              start_index, end_index = replacement_range(current_context_menu || {}, current_text)
              next_text = current_text[0...start_index].to_s + pasted_text + current_text[end_index..].to_s
              next_cursor = start_index + pasted_text.length
              update_menu(source_text_payload(next_text, next_cursor))
            end

            def replacement_range(menu, current_text)
              if replace_source_selection?(menu)
                start_index, end_index = Shoko::Shared::IndexRange.ordered(current_selection)
                return [
                  Shoko::Core::Services::GraphemeCursor.clamp(current_text, start_index),
                  Shoko::Core::Services::GraphemeCursor.ceiling(current_text, end_index),
                ]
              end

              index = Shoko::Core::Services::GraphemeCursor.clamp(
                current_text, menu.fetch(:paste_index, current_source_cursor)
              )
              [index, index]
            end

            def replace_source_selection?(menu)
              menu[:replace_selection] == true && source_selection?(current_selection)
            end

            def source_text_payload(next_text, next_cursor)
              {
                mode: :translator,
                translator_focus: :input,
                translator_input_text: next_text,
                translator_input_cursor: next_cursor,
                translator_selection: nil,
                translator_context_menu: nil,
              }
            end

            def focus_source_input(index)
              text = @menu_state_reader.translator_input_text.to_s
              update_menu(
                mode: :translator,
                translator_focus: :input,
                translator_input_cursor: Shoko::Core::Services::GraphemeCursor.clamp(text, index),
                translator_selection: nil,
                translator_context_menu: nil
              )
            end

            def paste_target_for(hit, selection)
              return [current_source_cursor, false] unless hit[:kind] == :source
              return [hit[:index], false] unless source_selection?(selection)

              [Shoko::Shared::IndexRange.ordered(selection).first, true]
            end

            def notify_and_dismiss(message)
              notify(message)
              clear_context_menu!
            end
          end
        end
      end
    end
  end
end
