# frozen_string_literal: true

require_relative '../dependencies/menu_controller_dependencies'
require_relative '../../../../shared/text_sanitizer'
require_relative '../../../../shared/menu_definitions'
require_relative '../../../../core/ports/inbound/menu_intent_handler'

require_relative 'state_controller'
require_relative 'input_controller'
require_relative 'actions/lifecycle_actions'
require_relative 'actions/navigation_actions'
require_relative 'actions/download_actions'
require_relative 'actions/dictionary_actions'
require_relative 'actions/settings_actions'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Controller responsible for the menu orchestration loop.
          class Controller
            include Shoko::Core::Ports::Inbound::MenuIntentHandler
            include Actions::Lifecycle
            include Actions::Navigation
            include Actions::Download
            include Actions::Dictionary
            include Actions::Settings

            SETTINGS_ACTIONS = Shoko::Shared::MenuDefinitions.settings_actions
            SETTINGS_MAX_INDEX = SETTINGS_ACTIONS.length - 1

            attr_accessor :filtered_epubs
            attr_reader :observer_registry, :main_menu_component, :catalog,
                        :terminal_service, :frame_coordinator, :render_pipeline,
                        :state_controller, :input_controller, :menu_state_reader, :menu_state_writer,
                        :command_bus

            def command_logger
              @logger_ref
            end

            def handle_menu_intent(intent_symbol, payload = nil)
              key = payload&.key

              case intent_symbol.to_sym
              when :annotation_editor_backspace then annotation_editor_backspace(key)
              when :annotation_editor_cancel then annotation_editor_cancel(key)
              when :annotation_editor_enter then annotation_editor_enter(key)
              when :annotation_editor_insert_char then annotation_editor_insert_char(key)
              when :annotation_editor_move_down then annotation_editor_move_down(key)
              when :annotation_editor_move_left then annotation_editor_move_left(key)
              when :annotation_editor_move_right then annotation_editor_move_right(key)
              when :annotation_editor_move_up then annotation_editor_move_up(key)
              when :annotation_editor_save then annotation_editor_save(key)
              when :annotations_down then annotations_down(key)
              when :annotations_select then annotations_select(key)
              when :annotations_up then annotations_up(key)
              when :browse_down then browse_down(key)
              when :browse_up then browse_up(key)
              when :delete_selected_annotation then delete_selected_annotation(key)
              when :dictionary_back then dictionary_back(key)
              when :dictionary_down then dictionary_down(key)
              when :dictionary_exit_search then dictionary_exit_search(key)
              when :dictionary_refresh then dictionary_refresh(key)
              when :dictionary_search_backspace then dictionary_search_backspace(key)
              when :dictionary_search_delete then dictionary_search_delete(key)
              when :dictionary_search_insert_char then dictionary_search_insert_char(key)
              when :dictionary_select then dictionary_select(key)
              when :dictionary_start_search then dictionary_start_search(key)
              when :dictionary_submit_search then dictionary_submit_search(key)
              when :dictionary_up then dictionary_up(key)
              when :download_confirm then download_confirm(key)
              when :download_down then download_down(key)
              when :download_exit_search then download_exit_search(key)
              when :download_next_page then download_next_page(key)
              when :download_prev_page then download_prev_page(key)
              when :download_refresh then download_refresh(key)
              when :download_search_backspace then download_search_backspace(key)
              when :download_search_delete then download_search_delete(key)
              when :download_search_insert_char then download_search_insert_char(key)
              when :download_start_search then download_start_search(key)
              when :download_submit_search then download_submit_search(key)
              when :download_up then download_up(key)
              when :library_down then library_down(key)
              when :library_select then library_select(key)
              when :library_toggle_details then library_toggle_details(key)
              when :library_up then library_up(key)
              when :menu_back_to_root then menu_back_to_root(key)
              when :menu_nav_down then menu_nav_down(key)
              when :menu_nav_up then menu_nav_up(key)
              when :menu_quit then menu_quit(key)
              when :menu_select then menu_select(key)
              when :open_selected_annotation then open_selected_annotation(key)
              when :open_selected_annotation_for_edit then open_selected_annotation_for_edit(key)
              when :open_selected_book then open_selected_book(key)
              when :search_backspace then search_backspace(key)
              when :search_delete then search_delete(key)
              when :search_insert_char then search_insert_char(key)
              when :settings_down then settings_down(key)
              when :settings_select then settings_select(key)
              when :settings_up then settings_up(key)
              when :switch_to_annotations_mode then switch_to_annotations_mode(key)
              when :switch_to_browse then switch_to_browse(key)
              when :switch_to_search then switch_to_search(key)
              else
                raise ArgumentError, "Unsupported menu intent: #{intent_symbol}"
              end
            end

            def initialize(deps:)
              deps.validate!

              @observer_registry = deps.observer_registry
              @catalog = deps.catalog
              @terminal_service = deps.terminal_service
              @frame_coordinator = deps.frame_coordinator
              @render_pipeline = deps.render_pipeline
              @main_menu_component = deps.ui_component_factory.main_menu_component(
                controller: self,
                menu_ui_dependencies: deps.menu_ui_dependencies
              )
              @filtered_epubs = []
              @notification_service = deps.notification_service
              @settings_service_ref = deps.settings_service
              @annotation_service_ref = deps.annotation_service
              @logger_ref = deps.logger
              @menu_state_reader = deps.menu_state_reader
              @menu_state_writer = deps.menu_state_writer
              @command_bus = deps.command_bus
              @file_probe = deps.file_probe
              @path_ops = deps.path_ops
              @clock = deps.clock
              @process_control = deps.process_control

              raise ArgumentError, 'state_controller_factory is required' if deps.state_controller_factory.nil?
              @state_controller = deps.state_controller_factory.call(self)
              @input_controller = InputController.new(
                self,
                key_classifier: deps.key_classifier,
                input_system_factory: deps.input_system_factory
              )
              @dispatcher = @input_controller.dispatcher
            end

            # Symbol-dispatch entry points for menu input bindings.
            def menu_nav_up(_key = nil)
              handle_navigation(:up)
            end

            def menu_nav_down(_key = nil)
              handle_navigation(:down)
            end

            def menu_select(_key = nil)
              handle_menu_selection
            end

            def menu_quit(_key = nil)
              cleanup_and_exit(0, '')
            end

            def menu_back_to_root(_key = nil)
              switch_to_mode(:menu)
            end

            def switch_to_annotations_mode(_key = nil)
              switch_to_mode(:annotations)
            end

            def browse_up(_key = nil)
              shift_browse_selection(-1)
            end

            def browse_down(_key = nil)
              shift_browse_selection(+1)
            end

            def settings_up(_key = nil)
              shift_settings_selection(-1)
            end

            def settings_down(_key = nil)
              shift_settings_selection(+1)
            end

            def settings_select(_key = nil)
              index = (@menu_state_reader&.settings_selected || 0).to_i
              action = SETTINGS_ACTIONS[index]
              return :pass unless action

              if action == :back_to_menu
                switch_to_mode(:menu)
              else
                execute_settings_action(action)
              end
            end

            def search_backspace(key = nil)
              update_query_with_edit(:search_query, :search_cursor, :backspace, key)
            end

            def search_delete(key = nil)
              update_query_with_edit(:search_query, :search_cursor, :delete, key)
            end

            def search_insert_char(key = nil)
              update_query_with_edit(:search_query, :search_cursor, :insert, key)
            end

            def dictionary_search_backspace(key = nil)
              update_query_with_edit(:dictionary_query, :dictionary_cursor, :backspace, key)
            end

            def dictionary_search_delete(key = nil)
              update_query_with_edit(:dictionary_query, :dictionary_cursor, :delete, key)
            end

            def dictionary_search_insert_char(key = nil)
              update_query_with_edit(:dictionary_query, :dictionary_cursor, :insert, key)
            end

            def download_search_backspace(key = nil)
              update_query_with_edit(:download_query, :download_cursor, :backspace, key)
            end

            def download_search_delete(key = nil)
              update_query_with_edit(:download_query, :download_cursor, :delete, key)
            end

            def download_search_insert_char(key = nil)
              update_query_with_edit(:download_query, :download_cursor, :insert, key)
            end

            def annotation_editor_cancel(_key = nil)
              editor = current_editor_component
              return :pass unless editor

              editor.cancel_annotation
              switch_to_mode(:annotations)
            end

            def annotation_editor_save(_key = nil)
              editor = current_editor_component
              return :pass unless editor

              editor.save_annotation
              switch_to_mode(:annotations)
            end

            def annotation_editor_backspace(_key = nil)
              editor = current_editor_component
              return :pass unless editor

              editor.handle_backspace
            end

            def annotation_editor_enter(_key = nil)
              editor = current_editor_component
              return :pass unless editor

              editor.handle_enter
            end

            def annotation_editor_move_left(_key = nil)
              editor = current_editor_component
              return :pass unless editor

              editor.handle_move_left
            end

            def annotation_editor_move_right(_key = nil)
              editor = current_editor_component
              return :pass unless editor

              editor.handle_move_right
            end

            def annotation_editor_move_up(_key = nil)
              editor = current_editor_component
              return :pass unless editor

              editor.handle_move_up
            end

            def annotation_editor_move_down(_key = nil)
              editor = current_editor_component
              return :pass unless editor

              editor.handle_move_down
            end

            def annotation_editor_insert_char(key = nil)
              char = key.to_s
              return :pass unless Shoko::Shared::TextSanitizer.printable_char?(char)

              editor = current_editor_component
              return :pass unless editor

              editor.handle_character(char)
            end

            # Public workflow API for reader-launch book selection.
            def selected_book_for_reader_launch
              index = (@menu_state_reader.browse_selected || 0).to_i
              screen = main_menu_component.browse_screen
              screen.book_at(index)
            end

            # Public workflow API for annotation actions.
            def selected_annotation_for_workflow
              screen = @main_menu_component.annotations_screen
              {
                annotation: screen.current_annotation,
                book_path: screen.current_book_path
              }
            end

            # Public workflow API for annotation view refreshes.
            def refresh_annotations_view_for_workflow
              @main_menu_component.annotations_screen.refresh_data
            end

            private

            attr_reader :notification_service

            def logger
              @logger_ref
            end

            def settings_service
              @settings_service_ref
            end

            def preload_annotations
              return @menu_state_writer.update_menu(annotations_all: {}) unless @annotation_service_ref

              @menu_state_writer.update_menu(annotations_all: @annotation_service_ref.list_all)
            # resilient-boundary
            rescue StandardError => e
              logger&.error('menu.preload_annotations.failed', error: e.class.name, message: e.message)
              @menu_state_writer.update_menu(annotations_all: {})
            end

            def reset_download_state
              @menu_state_writer.update_menu(
                download_query: '',
                download_cursor: 0,
                download_selected: 0,
                download_results: [],
                download_count: 0,
                download_next: nil,
                download_prev: nil,
                download_status: :idle,
                download_message: '',
                download_progress: 0.0
              )
            end

            def reset_dictionary_state
              @menu_state_writer.update_menu(
                dictionary_selected: 0,
                dictionary_query: '',
                dictionary_cursor: 0,
                dictionary_results: [],
                dictionary_status: :idle,
                dictionary_message: '',
                dictionary_progress: 0.0
              )
            end

            def update_download_selection(delta)
              results = Array(@menu_state_reader.download_results)
              max_index = [results.length - 1, 0].max
              current = (@menu_state_reader.download_selected || 0).to_i
              new_val = (current + delta).clamp(0, max_index)
              @menu_state_writer.update_menu(download_selected: new_val)
            end

            def selected_download_book
              results = Array(@menu_state_reader.download_results)
              index = (@menu_state_reader.download_selected || 0).to_i
              results[index]
            end

            def selected_library_item
              screen = main_menu_component.library_screen
              items = screen.items
              index = @menu_state_reader.browse_selected || 0
              items[index]
            end

            def resolve_library_path(item)
              primary = item.open_path
              return primary if state_controller.valid_cache_path?(primary)

              nil
            end

            def file_exists?(path)
              @file_probe&.exist?(path)
            end

            def shift_browse_selection(delta)
              max_index = [browse_items_count.to_i - 1, 0].max
              current = (@menu_state_reader&.browse_selected || 0).to_i
              @menu_state_writer&.update_menu(browse_selected: (current + delta).clamp(0, max_index))
            end

            def shift_settings_selection(delta)
              current = (@menu_state_reader&.settings_selected || 0).to_i
              @menu_state_writer&.update_menu(settings_selected: (current + delta).clamp(0, SETTINGS_MAX_INDEX))
            end

            def update_query_with_edit(query_field, cursor_field, operation, key)
              current = menu_query_value(query_field)
              cursor = menu_cursor_value(cursor_field, current)
              cursor = cursor.clamp(0, current.length)

              new_text, new_cursor = case operation
                                     when :backspace
                                       return if cursor <= 0
                                       [current[0, cursor - 1].to_s + current[cursor..].to_s, cursor - 1]
                                     when :delete
                                       return if cursor >= current.length
                                       [current[0, cursor].to_s + current[(cursor + 1)..].to_s, cursor]
                                     when :insert
                                       char = key.to_s
                                       return unless Shoko::Shared::TextSanitizer.printable_char?(char)
                                       [current[0, cursor].to_s + char + current[cursor..].to_s, cursor + 1]
                                     else
                                       return
                                     end

              @menu_state_writer&.update_menu(query_field => new_text, cursor_field => new_cursor)
            end

            def execute_settings_action(action)
              case action
              when :toggle_view_mode then toggle_view_mode
              when :cycle_line_spacing then cycle_line_spacing
              when :toggle_page_numbering_mode then toggle_page_numbering_mode
              when :toggle_page_numbers then toggle_page_numbers
              when :toggle_highlight_quotes then toggle_highlight_quotes
              when :open_dictionary_settings then open_dictionary_settings
              when :toggle_kitty_images then toggle_kitty_images
              when :wipe_cache then wipe_cache
              when :toggle_wipe_cache_cached then toggle_wipe_cache_cached
              when :toggle_wipe_cache_downloads then toggle_wipe_cache_downloads
              when :toggle_wipe_cache_annotations then toggle_wipe_cache_annotations
              when :toggle_wipe_cache_bookmarks then toggle_wipe_cache_bookmarks
              when :toggle_wipe_cache_progress then toggle_wipe_cache_progress
              when :toggle_wipe_cache_config then toggle_wipe_cache_config
              when :toggle_wipe_cache_nuke then toggle_wipe_cache_nuke
              else
                raise ArgumentError, "Unsupported settings action: #{action}"
              end
            end

            def menu_query_value(field)
              case field
              when :search_query then @menu_state_reader.search_query.to_s
              when :dictionary_query then @menu_state_reader.dictionary_query.to_s
              when :download_query then @menu_state_reader.download_query.to_s
              else
                raise ArgumentError, "Unsupported query field: #{field}"
              end
            end

            def menu_cursor_value(field, current_text)
              value = case field
                      when :search_cursor then @menu_state_reader.search_cursor
                      when :dictionary_cursor then @menu_state_reader.dictionary_cursor
                      when :download_cursor then @menu_state_reader.download_cursor
                      else
                        raise ArgumentError, "Unsupported cursor field: #{field}"
                      end
              (value || current_text.length).to_i
            end
          end
        end
      end
    end
  end
end
