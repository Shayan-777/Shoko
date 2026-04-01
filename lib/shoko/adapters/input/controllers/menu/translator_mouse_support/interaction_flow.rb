# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          class TranslatorMouseSupport
            # Selection, drag, and context-menu opening flow for the translator mouse layer.
            module InteractionFlow
              private

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
            end
          end
        end
      end
    end
  end
end
