# frozen_string_literal: true

require_relative '../../../../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          module Actions
            # Menu controller lifecycle orchestration and main loop support.
            module Lifecycle
              def run
                bootstrap_catalog
                main_loop
              rescue Interrupt
                cleanup_and_exit(0, "\nGoodbye!")
              rescue Shoko::FatalExternalInputError => e
                log_fatal_external_input(e)
                cleanup_and_exit(2, "Fatal external input error: #{e.message}", e)
              # resilient-boundary
              rescue Shoko::Error => e
                cleanup_and_exit(1, "Error: #{e.message}", e)
              ensure
                ensure_terminal_cleanup
                @catalog.cleanup
              end

              def cleanup_and_exit(code, message, error = nil)
                cleanup_terminal

                log_exit(message, error)
                @process_control&.terminate(code)
              end

              def main_loop
                draw_screen
                loop do
                  process_scan_results_if_available
                  handle_user_input
                  draw_screen
                end
              end

              def handle_user_input
                sync_menu_mouse_tracking
                keys = read_input_keys(timeout: annotation_editor_active? ? blink_poll_interval : nil)
                remaining = consume_menu_mouse_input(keys)
                input_controller.handle_keys(remaining) unless remaining.empty?
              end

              def read_input_keys(timeout: nil)
                @terminal_service.read_keys_blocking(limit: 10, timeout: timeout)
              end

              def process_scan_results_if_available
                return unless (epubs = @catalog.process_results)

                @filtered_epubs = epubs
                @main_menu_component.browse_screen.filtered_epubs = epubs
                @main_menu_component.library_screen.invalidate_cache!
              end

              def draw_screen
                notification_service&.tick
                @frame_coordinator.with_frame do |surface, bounds, _w, _h|
                  @render_pipeline.render_component(surface, bounds, @main_menu_component)
                end
              end

              def annotation_editor_active?
                @menu_state_reader.mode == :annotation_editor
              rescue Shoko::Error => e
                raise if e.is_a?(Shoko::FatalExternalInputError)

                @logger_ref&.debug('menu.annotation_editor_active_check_failed',
                                   error: e.class.name,
                                   message: e.message)
                false
              end

              def blink_poll_interval
                0.1
              end

              private

              def cleanup_terminal
                terminal = terminal_service
                return unless terminal

                cleanup_error = nil
                begin
                  disable_menu_mouse_tracking
                  terminal.cleanup
                # resilient-boundary
                rescue Shoko::Error => e
                  cleanup_error = e
                  @logger_ref&.error('Menu terminal cleanup failed', error: e.message)
                ensure
                  force_cleanup_if_needed(terminal, cleanup_error)
                end
              end

              def force_cleanup_if_needed(terminal, cleanup_error)
                remaining_depth = terminal.session_depth || 0
                needs_force = cleanup_error || remaining_depth.positive?
                return unless needs_force

                terminal.force_cleanup
              # resilient-boundary
              rescue Shoko::Error => e
                @logger_ref&.error('Menu terminal force cleanup failed', error: e.message)
              end

              def log_exit(message, error)
                @logger_ref&.info('Exiting menu', message: message, status: error ? 'error' : 'ok')
                return unless error

                @logger_ref&.error('Menu exit error', error: error.message, backtrace: Array(error.backtrace))
              end

              def log_fatal_external_input(error)
                @logger_ref&.error(fatal_event_id_for(error), error: error.class.name, message: error.message)
              end

              def bootstrap_catalog
                @terminal_service.setup
                @catalog.load_cached
                epubs = @catalog.entries || []
                @filtered_epubs = epubs
                @main_menu_component.browse_screen.filtered_epubs = epubs
                @catalog.start_scan(force: true) if epubs.empty?
              end

              def sync_menu_mouse_tracking
                return enable_menu_mouse_tracking if translator_mouse_mode? && !@menu_mouse_tracking
                return disable_menu_mouse_tracking if !translator_mouse_mode? && @menu_mouse_tracking

                nil
              end

              def enable_menu_mouse_tracking
                @terminal_service.enable_mouse
                @menu_mouse_tracking = true
              end

              def disable_menu_mouse_tracking
                return unless @menu_mouse_tracking

                @terminal_service.disable_mouse
                @menu_mouse_tracking = false
              rescue Shoko::Error
                @menu_mouse_tracking = false
              end

              def consume_menu_mouse_input(keys)
                return Array(keys) unless translator_mouse_mode?

                Array(keys).each_with_object([]) do |key, remaining|
                  translator_mouse_sequence?(key) ? handle_translator_mouse_sequence(key) : remaining << key
                end
              end

              def translator_mouse_sequence?(token)
                @mouse_handler && @mouse_handler.mouse_sequence?(token)
              end

              def handle_translator_mouse_sequence(token)
                event = @mouse_handler.parse_mouse_event(token)
                return unless translator_click_release?(event)

                action = @main_menu_component.translator_screen.hit_test(event[:x] + 1, event[:y] + 1, translator_bounds)
                apply_translator_mouse_action(action)
              end

              def translator_click_release?(event)
                event && event[:released] && event[:button].to_i.zero?
              end

              def translator_bounds
                height, width = @terminal_service.size
                Struct.new(:width, :height).new(width, height)
              end

              def apply_translator_mouse_action(action)
                return unless action

                case action[:type]
                when :focus then focus_translator_input
                when :toggle_dropdown then toggle_translator_dropdown(action[:kind])
                when :select_language then select_translator_language(action)
                end
              end

              def focus_translator_input
                @menu_session_mutator.update_menu(mode: :translator, translator_focus: :input)
                input_controller.activate(:translator)
              end

              def toggle_translator_dropdown(kind)
                dropdown_mode = kind == :source ? :translator_source_dropdown : :translator_target_dropdown
                return close_translator_dropdown(kind) if @menu_state_reader.mode == dropdown_mode

                open_translator_dropdown(kind, dropdown_mode)
              end

              def close_translator_dropdown(kind)
                @menu_session_mutator.update_menu(mode: :translator, translator_focus: kind)
                input_controller.activate(:translator)
              end

              def open_translator_dropdown(kind, dropdown_mode)
                @menu_session_mutator.update_menu(
                  mode: dropdown_mode,
                  translator_focus: kind,
                  translator_dropdown_selected: translator_language_index(kind)
                )
                input_controller.activate(dropdown_mode)
              end

              def select_translator_language(action)
                field = action[:kind] == :source ? :translator_source_lang : :translator_target_lang
                @menu_session_mutator.update_menu(
                  {
                    mode: :translator,
                    translator_focus: action[:kind],
                    translator_dropdown_selected: action[:index],
                    field => action[:code],
                  }
                )
                input_controller.activate(:translator)
                translate_from_current_translator_state
              end

              def translate_from_current_translator_state
                text = @menu_state_reader.translator_input_text.to_s
                return if text.strip.empty?

                @state_controller.translate_text(
                  text: text,
                  source_lang: @menu_state_reader.translator_source_lang,
                  target_lang: @menu_state_reader.translator_target_lang
                )
              end

              def translator_language_index(kind)
                code = kind == :source ? @menu_state_reader.translator_source_lang : @menu_state_reader.translator_target_lang
                translator_language_options(kind).index { |item| item[:code] == code.to_s } || 0
              end

              def translator_language_options(kind)
                languages = Array(@menu_state_reader.translator_languages).map { |item| normalize_language(item) }
                kind == :source ? [{ code: 'auto', name: 'Auto Detect' }, *languages] : languages
              end

              def normalize_language(item)
                normalized = Shoko::Shared::HashNormalizer.symbolize_keys(item) || {}
                code = normalized[:code]
                name = normalized[:name]
                {
                  code: code.to_s,
                  name: name.to_s,
                }
              end

              def translator_mouse_mode?
                %i[translator translator_source_dropdown translator_target_dropdown].include?(@menu_state_reader.mode)
              end

              def ensure_terminal_cleanup
                @terminal_service.force_cleanup
              # resilient-boundary
              rescue Shoko::Error => e
                @logger_ref&.debug('menu.run.ensure_terminal_cleanup_failed', error: e.class.name, message: e.message)
              end

              def fatal_event_id_for(error)
                case error
                when Shoko::MalformedBookInputError
                  'fatal.external_input.book'
                when Shoko::MalformedMetadataInputError
                  'fatal.external_input.metadata'
                when Shoko::MalformedDictionaryInputError
                  'fatal.external_input.dictionary'
                else
                  'fatal.external_input.unknown'
                end
              end
            end
          end
        end
      end
    end
  end
end
