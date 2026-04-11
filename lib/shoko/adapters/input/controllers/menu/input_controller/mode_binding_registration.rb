# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          class InputController
            # Registers the higher-complexity menu submode bindings outside the controller body.
            module ModeBindingRegistration
              private

              def register_download_bindings
                bindings = {}
                add_nav_up_down(bindings, :move_download_selection_up, :move_download_selection_down)
                add_confirm_bindings(bindings, :activate_download_selection)
                bind_intent!(bindings, download_close_keys, :close_download_mode)
                bind_intent!(bindings, ['/'], :open_download_mode, payload: mode_change(:download_search))
                bind_intent!(bindings, %W[\t s S], :open_download_source_mode)
                bind_intent!(bindings, %w[n N], :download_next_page)
                bind_intent!(bindings, %w[p P], :download_prev_page)
                bind_intent!(bindings, ['r'], :refresh_download_results)
                dispatcher.register_mode(:download, bindings)
              end

              def register_download_search_bindings
                bindings = {}
                bind_intent!(bindings, @key_classifier.action_keys(:backspace), :download_query_backspace)
                bind_intent!(bindings, @key_classifier.action_keys(:delete), :download_query_delete)
                bindings[:__default__] = text_input_binding(:download_query_insert_text)
                add_confirm_bindings(bindings, :submit_download_query)
                bind_intent!(bindings, ['/'], :close_download_mode, payload: mode_change(:download))
                bind_intent!(bindings,
                             @key_classifier.action_keys(:cancel),
                             :close_download_mode,
                             payload: mode_change(:download))
                dispatcher.register_mode(:download_search, bindings)
              end

              def register_download_source_bindings
                bindings = {}
                bind_download_source_navigation(bindings)
                add_confirm_bindings(bindings, :activate_download_source_selection)
                bind_download_source_close(bindings, @key_classifier.action_keys(:cancel))
                bind_download_source_close(bindings, @key_classifier.action_keys(:quit))
                dispatcher.register_mode(:download_source_select, bindings)
              end

              def register_annotations_bindings
                bindings = {}
                add_nav_up_down(bindings, :move_annotation_selection_up, :move_annotation_selection_down)
                add_confirm_bindings(bindings, :activate_annotation_selection)
                bind_intent!(bindings, %w[e E], :edit_selected_annotation)
                bind_intent!(bindings, ['d'], :delete_selected_annotation)
                add_mode_change_bindings(bindings, :switch_to_menu_mode)
                dispatcher.register_mode(:annotations, bindings)
              end

              def register_annotation_detail_bindings
                bindings = {}
                bind_intent!(bindings, %w[o O], :open_selected_annotation)
                bind_intent!(bindings, %w[e E], :edit_selected_annotation)
                bind_intent!(bindings, ['d'], :delete_selected_annotation)
                bind_intent!(bindings, @key_classifier.action_keys(:cancel), :open_annotations_mode)
                dispatcher.register_mode(:annotation_detail, bindings)
              end

              def register_annotation_editor_bindings
                bindings = {}
                bind_intent!(bindings, @key_classifier.action_keys(:cancel), :annotation_editor_cancel)
                bind_intent!(bindings, @key_classifier.action_keys(:quit), :annotation_editor_cancel)
                bind_intent!(bindings, @key_classifier.action_keys(:save), :annotation_editor_save)
                bind_intent!(bindings, @key_classifier.action_keys(:backspace), :annotation_editor_backspace)
                bind_intent!(bindings, Array(@key_classifier.action_keys(:confirm)), :annotation_editor_newline)
                bind_annotation_editor_cursor_movements!(bindings)
                bindings[:__default__] = text_input_binding(:annotation_editor_insert_text)
                dispatcher.register_mode(:annotation_editor, bindings)
              end

              def bind_annotation_editor_cursor_movements!(bindings)
                bind_annotation_editor_cursor(bindings, :left, :annotation_editor_move_left)
                bind_annotation_editor_cursor(bindings, :right, :annotation_editor_move_right)
                bind_annotation_editor_cursor(bindings, :up, :annotation_editor_move_up)
                bind_annotation_editor_cursor(bindings, :down, :annotation_editor_move_down)
              end

              def register_rss_reader_bindings
                bindings = {}
                add_nav_up_down(bindings, :rss_reader_move_up, :rss_reader_move_down)
                bind_rss_reader_focus(bindings)
                bind_rss_reader_navigation(bindings)
                bind_rss_reader_scope(bindings)
                bind_rss_reader_article_actions(bindings)
                bind_rss_reader_input_actions(bindings)
                bind_rss_reader_close(bindings)
                dispatcher.register_mode(:rss_reader, bindings)
              end

              def register_rss_reader_feed_input_bindings
                bindings = {}
                bind_intent!(bindings, @key_classifier.action_keys(:backspace), :rss_reader_add_feed_backspace)
                bind_intent!(bindings, @key_classifier.action_keys(:delete), :rss_reader_add_feed_delete)
                bindings[:__default__] = text_input_binding(:rss_reader_add_feed_insert_text)
                add_confirm_bindings(bindings, :rss_reader_submit_add_feed)
                bind_intent!(bindings,
                             Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel)),
                             :close_rss_reader_mode,
                             payload: mode_change(:rss_reader))
                dispatcher.register_mode(:rss_reader_feed_input, bindings)
              end

              def register_rss_reader_filter_bindings
                bindings = {}
                bind_intent!(bindings, @key_classifier.action_keys(:backspace), :rss_reader_filter_backspace)
                bind_intent!(bindings, @key_classifier.action_keys(:delete), :rss_reader_filter_delete)
                bindings[:__default__] = text_input_binding(:rss_reader_filter_insert_text)
                add_confirm_bindings(bindings, :rss_reader_submit_filter)
                bind_intent!(bindings,
                             Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel)),
                             :close_rss_reader_mode,
                             payload: mode_change(:rss_reader))
                dispatcher.register_mode(:rss_reader_filter, bindings)
              end

              def download_close_keys
                Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
              end

              def download_source_prev_keys
                Array(@key_classifier.navigation_keys(:up)) + Array(@key_classifier.navigation_keys(:left))
              end

              def download_source_next_keys
                Array(@key_classifier.navigation_keys(:down)) + Array(@key_classifier.navigation_keys(:right))
              end

              def bind_download_source_navigation(bindings)
                bind_intent!(bindings, download_source_prev_keys, :move_download_source_selection_up,
                             payload: selection_delta(-1))
                bind_intent!(bindings, download_source_next_keys, :move_download_source_selection_down,
                             payload: selection_delta(1))
              end

              def bind_download_source_close(bindings, keys)
                bind_intent!(bindings, keys, :close_download_source_mode, payload: mode_change(:download))
              end

              def bind_annotation_editor_cursor(bindings, direction, intent)
                bind_intent!(bindings, @key_classifier.navigation_keys(direction), intent,
                             payload: cursor_move(direction))
              end

              def bind_rss_reader_focus(bindings)
                bind_intent!(bindings, @key_classifier.navigation_keys(:left), :rss_reader_focus_left)
                bind_intent!(bindings, @key_classifier.navigation_keys(:right), :rss_reader_focus_right)
                bind_intent!(bindings, @key_classifier.action_keys(:confirm), :rss_reader_activate_selection)
                bind_intent!(bindings, ["\t"], :rss_reader_cycle_focus)
                bind_intent!(bindings, ["\e[Z"], :rss_reader_cycle_focus_back)
              end

              def bind_rss_reader_navigation(bindings)
                bind_intent!(bindings, @key_classifier.action_keys(:space), :rss_reader_page_down)
                bind_intent!(bindings, %w[p P], :rss_reader_page_up)
                bind_intent!(bindings, ['g'], :rss_reader_go_top)
                bind_intent!(bindings, ['G'], :rss_reader_go_bottom)
                bind_intent!(bindings, %w[s S], :rss_reader_sync)
                bind_intent!(bindings, %w[z Z], :rss_reader_toggle_zen)
              end

              def bind_rss_reader_scope(bindings)
                bind_intent!(bindings, ['1'], :rss_reader_show_all)
                bind_intent!(bindings, ['2'], :rss_reader_show_unread)
                bind_intent!(bindings, ['3'], :rss_reader_show_starred)
              end

              def bind_rss_reader_article_actions(bindings)
                bind_intent!(bindings, ['r'], :rss_reader_mark_read)
                bind_intent!(bindings, %w[u U], :rss_reader_mark_unread)
                bind_intent!(bindings, %w[m M], :rss_reader_mark_starred)
                bind_intent!(bindings, %w[v V], :rss_reader_unstar)
                bind_intent!(bindings, ['d'], :rss_reader_remove_feed)
              end

              def bind_rss_reader_input_actions(bindings)
                bind_intent!(bindings, %w[a A], :rss_reader_open_add_feed)
                bind_intent!(bindings, ['/'], :rss_reader_open_filter)
              end

              def bind_rss_reader_close(bindings)
                keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
                bind_intent!(bindings, keys, :close_rss_reader_mode)
              end
            end
          end
        end
      end
    end
  end
end
