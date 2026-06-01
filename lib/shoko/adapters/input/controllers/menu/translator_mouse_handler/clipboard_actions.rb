# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          class TranslatorMouseHandler
            # Clipboard action execution for the translator context menu.
            module ClipboardActions
              private

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
                start_index, end_index = replacement_range(current_context_menu || {}, current_text.length)
                next_text = current_text[0...start_index].to_s + pasted_text + current_text[end_index..].to_s
                next_cursor = start_index + pasted_text.length
                update_menu(source_text_payload(next_text, next_cursor))
              end

              def replacement_range(menu, current_length)
                return selection_bounds(current_selection) if replace_source_selection?(menu)

                index = menu.fetch(:paste_index, current_source_cursor).to_i.clamp(0, current_length)
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
                update_menu(
                  mode: :translator,
                  translator_focus: :input,
                  translator_input_cursor: index.to_i.clamp(0, translator_input_length),
                  translator_selection: nil,
                  translator_context_menu: nil
                )
              end

              def paste_target_for(hit, selection)
                return [current_source_cursor, false] unless hit[:kind] == :source
                return [hit[:index], false] unless source_selection?(selection)

                [selection_bounds(selection).first, true]
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
end
