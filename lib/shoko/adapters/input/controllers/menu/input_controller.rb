# frozen_string_literal: true

require 'shoko/shared/text_sanitizer'
require 'shoko/application/use_cases/requests/text_input'
require 'shoko/application/use_cases/requests/edit_op'
require 'shoko/application/use_cases/requests/selection_delta'
require 'shoko/application/use_cases/requests/cursor_move'
require 'shoko/application/use_cases/requests/mode_change'
require_relative '../../intent_binding'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Centralises dispatcher setup and key handling for the main menu.
          class InputController
            BINDING_REGISTRATIONS = %i[
              register_menu_bindings
              register_browse_bindings
              register_search_bindings
              register_library_bindings
              register_settings_bindings
              register_dictionary_bindings
              register_dictionary_search_bindings
              register_translator_packs_bindings
              register_translator_packs_search_bindings
              register_download_bindings
              register_download_search_bindings
              register_download_source_bindings
              register_translator_bindings
              register_translator_source_dropdown_bindings
              register_translator_target_dropdown_bindings
              register_rss_reader_bindings
              register_rss_reader_feed_input_bindings
              register_rss_reader_filter_bindings
              register_rss_reader_find_bindings
              register_rss_reader_lookup_bindings
              register_annotations_bindings
              register_annotation_detail_bindings
              register_annotation_editor_bindings
            ].freeze

            attr_reader :dispatcher

            def initialize(menu, key_classifier:, input_system_factory:, intent_handler:)
              @menu = menu
              @key_classifier = key_classifier
              @dispatcher = input_system_factory.create_menu_dispatcher(intent_handler: intent_handler)
              register_bindings
              activate_current_mode
            end

            def handle_keys(keys)
              keys.each { |key| dispatcher.handle_key(key) }
            end

            def activate(mode)
              dispatcher.activate(mode)
            end

            private

            attr_reader :menu

            def register_bindings
              BINDING_REGISTRATIONS.each { |registration| method(registration).call }
            end

            def activate_current_mode
              current_mode = menu.menu_state_reader&.mode
              dispatcher.activate(current_mode)
            end

            def register_dictionary_search_bindings
              bindings = {}
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_menu_dictionary_query,
                           payload: edit_op(:backspace))
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_menu_dictionary_query,
                           payload: edit_op(:delete))
              bindings[:__default__] = edit_op_text_binding(:edit_menu_dictionary_query)
              add_confirm_bindings(bindings, :submit_dictionary_query)
              bind_intent!(bindings, ['/'], :close_dictionary_mode, payload: mode_change(:dictionary))
              bind_intent!(bindings,
                           @key_classifier.action_keys(:cancel),
                           :close_dictionary_mode,
                           payload: mode_change(:dictionary))
              dispatcher.register_mode(:dictionary_search, bindings)
            end

            def register_translator_dropdown_bindings(mode)
              bindings = {}
              add_nav_up_down(
                bindings,
                :move_translator_language_selection_up,
                :move_translator_language_selection_down
              )
              add_confirm_bindings(bindings, :activate_translator_language_selection)
              bind_intent!(bindings, @key_classifier.action_keys(:space), :activate_translator_language_selection)
              keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
              bind_intent!(bindings, keys, :close_translator_dropdown)
              dispatcher.register_mode(mode, bindings)
            end

            def add_confirm_bindings(bindings, action)
              bind_intent!(bindings, @key_classifier.action_keys(:confirm), action)
              bindings
            end

            def register_translator_source_dropdown_bindings
              register_translator_dropdown_bindings(:translator_source_dropdown)
            end

            def register_translator_target_dropdown_bindings
              register_translator_dropdown_bindings(:translator_target_dropdown)
            end

            def add_nav_up_down(bindings, up_action, down_action)
              bind_intent!(bindings, @key_classifier.navigation_keys(:up), up_action, payload: selection_delta(-1))
              bind_intent!(bindings, @key_classifier.navigation_keys(:down), down_action, payload: selection_delta(1))
              bindings
            end

            def bind_search_navigation(bindings)
              add_nav_up_down(bindings, :move_browse_selection_up, :move_browse_selection_down)
            end

            def add_mode_change_bindings(bindings, action)
              keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
              bind_intent!(bindings, keys, action)
              bindings
            end

            def bind_intent!(bindings, keys, intent, payload: nil)
              binding = Adapters::Input::IntentBinding.new(intent, payload: payload)
              Array(keys).each { |key| bindings[key] = binding }
              bindings
            end

            def text_input_binding(intent)
              Adapters::Input::IntentBinding.new(intent) do |key|
                char = key.to_s
                if Shoko::Shared::TextSanitizer.printable_char?(char)
                  Shoko::Application::UseCases::Requests::TextInput.new(text: char)
                else
                  Adapters::Input::IntentBinding.skip
                end
              end
            end

            def edit_op_text_binding(intent)
              Adapters::Input::IntentBinding.new(intent) do |key|
                char = key.to_s
                if Shoko::Shared::TextSanitizer.printable_char?(char)
                  Shoko::Application::UseCases::Requests::EditOp.new(operation: :insert, text: char)
                else
                  Adapters::Input::IntentBinding.skip
                end
              end
            end

            def edit_op(operation)
              Shoko::Application::UseCases::Requests::EditOp.new(operation: operation)
            end

            def selection_delta(delta)
              Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: delta)
            end

            def cursor_move(direction)
              Shoko::Application::UseCases::Requests::CursorMove.new(direction: direction)
            end

            def mode_change(mode)
              Shoko::Application::UseCases::Requests::ModeChange.new(mode: mode)
            end

            def register_menu_bindings
              bindings = {}
              bind_intent!(bindings,
                           @key_classifier.navigation_keys(:up),
                           :move_menu_selection_up,
                           payload: selection_delta(-1))
              bind_intent!(bindings,
                           @key_classifier.navigation_keys(:down),
                           :move_menu_selection_down,
                           payload: selection_delta(1))
              bind_intent!(bindings, @key_classifier.action_keys(:confirm), :activate_menu_selection)
              bind_intent!(bindings, @key_classifier.action_keys(:quit), :quit_application)
              dispatcher.register_mode(:menu, bindings)
            end

            def register_browse_bindings
              bindings = {}
              bind_intent!(bindings,
                           @key_classifier.navigation_keys(:up),
                           :move_browse_selection_up,
                           payload: selection_delta(-1))
              bind_intent!(bindings,
                           @key_classifier.navigation_keys(:down),
                           :move_browse_selection_down,
                           payload: selection_delta(1))
              bind_intent!(bindings, @key_classifier.action_keys(:confirm), :open_selected_book)
              add_mode_change_bindings(bindings, :switch_to_menu_mode)
              bind_intent!(bindings, ['/'], :switch_to_search_mode)
              dispatcher.register_mode(:browse, bindings)
            end

            def register_search_bindings
              bindings = {}
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_browse_search,
                           payload: edit_op(:backspace))
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_browse_search,
                           payload: edit_op(:delete))
              bindings[:__default__] = edit_op_text_binding(:edit_browse_search)
              bind_search_navigation(bindings)
              bind_intent!(bindings, @key_classifier.action_keys(:confirm), :open_selected_book)
              bind_intent!(bindings, ['/'], :switch_to_browse_mode)
              bind_intent!(bindings, @key_classifier.action_keys(:cancel), :switch_to_browse_mode)
              dispatcher.register_mode(:search, bindings)
            end

            def register_library_bindings
              bindings = {}
              add_nav_up_down(bindings, :move_library_selection_up, :move_library_selection_down)
              add_confirm_bindings(bindings, :activate_library_selection)
              bind_intent!(bindings, @key_classifier.action_keys(:space), :toggle_library_details)
              add_mode_change_bindings(bindings, :switch_to_menu_mode)
              dispatcher.register_mode(:library, bindings)
            end

            def register_settings_bindings
              bindings = {}
              bind_intent!(bindings,
                           @key_classifier.navigation_keys(:up),
                           :move_settings_selection_up,
                           payload: selection_delta(-1))
              bind_intent!(bindings,
                           @key_classifier.navigation_keys(:down),
                           :move_settings_selection_down,
                           payload: selection_delta(1))
              bind_intent!(bindings, @key_classifier.action_keys(:confirm), :activate_settings_selection)
              bind_intent!(bindings, @key_classifier.action_keys(:space), :activate_settings_selection)
              add_mode_change_bindings(bindings, :switch_to_menu_mode)
              dispatcher.register_mode(:settings, bindings)
            end

            def register_dictionary_bindings
              bindings = {}
              add_nav_up_down(bindings, :move_dictionary_selection_up, :move_dictionary_selection_down)
              add_confirm_bindings(bindings, :activate_dictionary_selection)
              bind_intent!(bindings, @key_classifier.action_keys(:space), :activate_dictionary_selection)
              keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
              bind_intent!(bindings, keys, :close_dictionary_mode)
              bind_intent!(bindings, ['/'], :open_dictionary_mode, payload: mode_change(:dictionary_search))
              bind_intent!(bindings, ['r'], :refresh_dictionary_results)
              dispatcher.register_mode(:dictionary, bindings)
            end

            def register_translator_packs_bindings
              bindings = {}
              add_nav_up_down(bindings, :move_translator_packs_selection_up, :move_translator_packs_selection_down)
              add_confirm_bindings(bindings, :activate_translator_packs_selection)
              bind_intent!(bindings, @key_classifier.action_keys(:space), :activate_translator_packs_selection)
              keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
              bind_intent!(bindings, keys, :close_translator_packs_mode)
              bind_intent!(bindings, ['/'], :open_translator_packs_mode, payload: mode_change(:translator_packs_search))
              bind_intent!(bindings, ['r'], :refresh_translator_packs)
              dispatcher.register_mode(:translator_packs, bindings)
            end

            def register_translator_packs_search_bindings
              bindings = {}
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_translator_packs_query,
                           payload: edit_op(:backspace))
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_translator_packs_query,
                           payload: edit_op(:delete))
              bindings[:__default__] = edit_op_text_binding(:edit_translator_packs_query)
              add_confirm_bindings(bindings, :submit_translator_packs_query)
              bind_intent!(bindings, ['/'], :close_translator_packs_mode, payload: mode_change(:translator_packs))
              bind_intent!(bindings,
                           @key_classifier.action_keys(:cancel),
                           :close_translator_packs_mode,
                           payload: mode_change(:translator_packs))
              dispatcher.register_mode(:translator_packs_search, bindings)
            end

            def register_translator_bindings
              bindings = {}
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_translator_input,
                           payload: edit_op(:backspace))
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_translator_input,
                           payload: edit_op(:delete))
              # Enter inserts a newline while editing (note-editor parity); Alt+Enter translates.
              # Terminals encode Alt+Enter differently — ESC+CR/LF (Meta prefix), or the CSI-u /
              # modifyOtherKeys forms — so accept all of them. (A lone ESC still closes the screen.)
              bind_intent!(bindings, @key_classifier.action_keys(:confirm), :translator_activate_focus)
              bind_intent!(bindings, ["\e\r", "\e\n", "\e[13;3u", "\e[27;3;13~"], :translator_submit)
              bind_intent!(bindings, ["\t"], :translator_cycle_focus)
              bind_intent!(bindings, ['S'], :translator_swap_languages)
              bind_translator_cursor_movements!(bindings)
              # Only Esc closes the translator — 'q' (the other mode-change key) must stay typeable.
              bind_intent!(bindings, @key_classifier.action_keys(:cancel), :close_translator_mode)
              bindings[:__default__] = edit_op_text_binding(:edit_translator_input)
              dispatcher.register_mode(:translator, bindings)
            end

            # Only the arrow-key escape sequences move the input cursor — the vim letters in
            # NAVIGATION (h/j/k/l) must stay typeable, so they are filtered out here.
            def bind_translator_cursor_movements!(bindings)
              %i[left right up down].each do |direction|
                keys = @key_classifier.navigation_keys(direction)
                                      .reject { |key| Shoko::Shared::TextSanitizer.printable_char?(key) }
                bind_intent!(bindings, keys, :move_translator_cursor, payload: cursor_move(direction))
              end
            end

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
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_download_query,
                           payload: edit_op(:backspace))
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_download_query,
                           payload: edit_op(:delete))
              bindings[:__default__] = edit_op_text_binding(:edit_download_query)
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
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_annotation_text,
                           payload: edit_op(:backspace))
              bind_intent!(bindings, Array(@key_classifier.action_keys(:confirm)), :edit_annotation_text,
                           payload: edit_op(:newline))
              bind_annotation_editor_cursor_movements!(bindings)
              bindings[:__default__] = edit_op_text_binding(:edit_annotation_text)
              dispatcher.register_mode(:annotation_editor, bindings)
            end

            def bind_annotation_editor_cursor_movements!(bindings)
              bind_annotation_editor_cursor(bindings, :left)
              bind_annotation_editor_cursor(bindings, :right)
              bind_annotation_editor_cursor(bindings, :up)
              bind_annotation_editor_cursor(bindings, :down)
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
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_rss_feed_input,
                           payload: edit_op(:backspace))
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_rss_feed_input,
                           payload: edit_op(:delete))
              bindings[:__default__] = edit_op_text_binding(:edit_rss_feed_input)
              add_confirm_bindings(bindings, :rss_reader_submit_add_feed)
              bind_intent!(bindings,
                           Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel)),
                           :close_rss_reader_mode,
                           payload: mode_change(:rss_reader))
              dispatcher.register_mode(:rss_reader_feed_input, bindings)
            end

            def register_rss_reader_filter_bindings
              bindings = {}
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_rss_filter,
                           payload: edit_op(:backspace))
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_rss_filter,
                           payload: edit_op(:delete))
              bindings[:__default__] = edit_op_text_binding(:edit_rss_filter)
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

            def bind_annotation_editor_cursor(bindings, direction)
              bind_intent!(bindings, @key_classifier.navigation_keys(direction), :move_annotation_cursor,
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
              bind_rss_reader_text_actions(bindings)
            end

            # Text interaction while reading, in the book reader's key language:
            # f finds, n/N step the matches, and the selection actions answer to
            # the same letters the reader's popup uses.
            def bind_rss_reader_text_actions(bindings)
              bind_intent!(bindings, %w[f F], :rss_reader_open_find)
              bind_intent!(bindings, ['n'], :rss_reader_next_match)
              bind_intent!(bindings, ['N'], :rss_reader_prev_match)
              bind_intent!(bindings, %w[y Y], :rss_reader_copy_selection)
              bind_intent!(bindings, %w[d D], :rss_reader_lookup_selection)
              bind_intent!(bindings, %w[t T], :rss_reader_translate_selection)
              bind_intent!(bindings, %w[m M], :rss_reader_annotate_selection)
            end

            def register_rss_reader_lookup_bindings
              bindings = {}
              add_nav_up_down(bindings, :rss_reader_move_up, :rss_reader_move_down)
              keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
              bind_intent!(bindings, keys, :close_rss_reader_mode, payload: mode_change(:rss_reader))
              dispatcher.register_mode(:rss_reader_lookup, bindings)
            end

            def register_rss_reader_find_bindings
              bindings = {}
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_rss_find,
                           payload: edit_op(:backspace))
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_rss_find,
                           payload: edit_op(:delete))
              bindings[:__default__] = edit_op_text_binding(:edit_rss_find)
              add_confirm_bindings(bindings, :rss_reader_submit_find)
              bind_intent!(bindings, @key_classifier.action_keys(:cancel), :rss_reader_close_find)
              dispatcher.register_mode(:rss_reader_find, bindings)
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
