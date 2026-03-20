# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      class ReaderInputController
        # Registers read-mode bindings and sidebar-aware navigation outside the controller body.
        module ReadModeBindingRegistration
          private

          def register_read_bindings
            bindings = {}
            bindings.merge!(reader_navigation_bindings)
            bindings.merge!(read_mode_local_bindings)
            @dispatcher.register_mode(:read, bindings)
          end

          def read_mode_local_bindings
            reader = Shoko::Shared::KeyDefinitions::READER
            actions = Shoko::Shared::KeyDefinitions::ACTIONS
            bindings = {}
            bind_reader_display_controls(bindings, reader)
            bind_reader_sidebar_controls(bindings, reader)
            bind_reader_session_controls(bindings, reader, actions)
            bindings
          end

          def bind_reader_display_controls(bindings, reader)
            bind_intent!(bindings, reader[:toggle_view], :toggle_view_mode)
            bind_intent!(bindings, reader[:toggle_page_mode], :toggle_page_numbering_mode)
            bind_intent!(bindings, reader[:increase_spacing], :increase_line_spacing)
            bind_intent!(bindings, reader[:decrease_spacing], :decrease_line_spacing)
            bind_intent!(bindings, reader[:show_help], :open_help_overlay)
            bind_intent!(bindings, reader[:rebuild_pagination], :rebuild_pagination) if reader.key?(:rebuild_pagination)
            bind_optional_reader_action(bindings, reader, :invalidate_pagination, :clear_pagination_cache)
          end

          def bind_reader_sidebar_controls(bindings, reader)
            bind_intent!(bindings, reader[:show_toc], :open_toc_sidebar)
            bind_intent!(bindings, reader[:show_bookmarks], :open_bookmarks_sidebar)
            bind_optional_reader_action(bindings, reader, :show_annotations_tab, :open_annotations_sidebar)
            bind_optional_reader_action(bindings, reader, :show_annotations, :open_annotations_overlay)
            bind_optional_reader_action(bindings, reader, :in_book_search, :open_in_book_search)
          end

          def bind_reader_session_controls(bindings, reader, actions)
            bind_intent!(bindings, reader[:add_bookmark], :add_bookmark)
            bind_intent!(bindings, actions[:quit], :quit_to_menu)
            bind_intent!(bindings, actions[:force_quit], :quit_application)
          end

          def reader_navigation_bindings
            reader = Shoko::Shared::KeyDefinitions::READER
            bindings = {}
            bind_static_reader_navigation!(bindings, reader)
            bind_sidebar_aware_reader_navigation!(bindings)
            bindings
          end

          def bind_static_reader_navigation!(bindings, reader)
            bind_intent!(bindings, reader[:next_page], :next_page)
            bind_intent!(bindings, reader[:prev_page], :prev_page)
            bind_intent!(bindings, reader[:next_chapter], :next_chapter)
            bind_intent!(bindings, reader[:prev_chapter], :prev_chapter)
            bind_intent!(bindings, reader[:go_to_start], :go_to_start)
            bind_intent!(bindings, reader[:go_to_end], :go_to_end)
          end

          def bind_sidebar_aware_reader_navigation!(bindings)
            bind_sidebar_move_down!(bindings)
            bind_sidebar_move_up!(bindings)
            bind_sidebar_aware_action!(bindings, :confirm) do
              sidebar_visible? ? IntentBinding.new(:sidebar_activate) : IntentBinding.new(:next_page)
            end
            bind_sidebar_aware_action!(bindings, :space) do
              sidebar_toc_active? ? IntentBinding.new(:toggle_sidebar) : IntentBinding.new(:next_page)
            end
          end

          def bind_sidebar_aware_action!(bindings, key, &)
            bind_dynamic_intent!(bindings, sidebar_navigation_keyset(key), &)
          end

          def sidebar_navigation_keyset(key)
            case key
            when :confirm, :space then Shoko::Shared::KeyDefinitions::ACTIONS[key]
            else Shoko::Shared::KeyDefinitions::NAVIGATION[key]
            end
          end

          def sidebar_visible?
            reader_state_reader&.sidebar_visible?
          end

          def sidebar_toc_active?
            sidebar_visible? && reader_state_reader&.sidebar_active_tab == :toc
          end

          def bind_sidebar_move_down!(bindings)
            bind_sidebar_aware_action!(bindings, :down) do
              sidebar_visible? ? sidebar_move_binding(1) : IntentBinding.new(:scroll_down)
            end
          end

          def bind_sidebar_move_up!(bindings)
            bind_sidebar_aware_action!(bindings, :up) do
              sidebar_visible? ? sidebar_move_binding(-1) : IntentBinding.new(:scroll_up)
            end
          end

          def sidebar_move_binding(delta)
            intent = delta.positive? ? :sidebar_move_down : :sidebar_move_up
            IntentBinding.new(intent, payload: selection_delta(delta))
          end

          def bind_optional_reader_action(bindings, reader, key, intent)
            return unless reader.key?(key)

            bind_intent!(bindings, reader[key], intent)
          end
        end
      end
    end
  end
end
