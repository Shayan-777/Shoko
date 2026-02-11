# frozen_string_literal: true

require_relative '../../../../core/ports/dictionary_ui_session'
require_relative '../../../input/key_definitions'

module Shoko
  module Adapters
    module Output
      module Ui
        module Sessions
          # Adapter-owned lifecycle for dictionary panel/popup UI components.
          class DictionaryUiSessionAdapter
            include Core::Ports::DictionaryUiSession

            def initialize(reader_state_reader:, state_writer:, ui_component_factory:)
              @reader_state_reader = reader_state_reader
              @state_writer = state_writer
              @ui_component_factory = ui_component_factory
            end

            def show_panel(result)
              panel = current_panel || @ui_component_factory&.dictionary_panel(@reader_state_reader)
              return false unless panel

              current_popup&.hide
              panel.show(result)
              @state_writer.update_reader(
                dictionary_panel: panel,
                dictionary_popup: nil,
                dictionary_visible: true,
                mode: :dictionary,
                popup_menu: nil
              )
              true
            rescue StandardError
              false
            end

            def show_popup(result)
              popup = current_popup || @ui_component_factory&.dictionary_popup
              return false unless popup

              current_panel&.hide
              popup.show(result)
              @state_writer.update_reader(
                dictionary_panel: nil,
                dictionary_popup: popup,
                dictionary_visible: true,
                mode: :dictionary,
                popup_menu: nil
              )
              true
            rescue StandardError
              false
            end

            def close
              current_panel&.hide
              current_popup&.hide
              @state_writer.update_reader(
                dictionary_panel: nil,
                dictionary_popup: nil,
                dictionary_visible: false,
                mode: :read
              )
              true
            rescue StandardError
              false
            end

            def visible?
              panel_visible? || popup_visible?
            end

            def panel_visible?
              component_visible?(current_panel)
            end

            def popup_visible?
              component_visible?(current_popup)
            end

            def active_result
              return current_panel.result if panel_visible? && current_panel.respond_to?(:result)
              return current_popup.result if popup_visible? && current_popup.respond_to?(:result)

              nil
            rescue StandardError
              nil
            end

            def active_kind
              return :panel if panel_visible?
              return :popup if popup_visible?

              nil
            end

            def insert_char(char)
              dispatch_key(char.to_s)
            end

            def backspace
              key = Adapters::Input::KeyDefinitions::ACTIONS[:backspace].first
              dispatch_key(key)
            end

            def confirm
              key = Adapters::Input::KeyDefinitions::ACTIONS[:confirm].first
              dispatch_key(key)
            end

            def cancel
              key = Adapters::Input::KeyDefinitions::ACTIONS[:cancel].first
              dispatch_key(key)
            end

            def tab
              dispatch_key("\t")
            end

            def swap_languages
              dispatch_key('S')
            end

            def scroll_up
              if setup_mode?
                key = Adapters::Input::KeyDefinitions::NAVIGATION[:up].first
                return !!dispatch_key(key)
              end

              component = active_component
              return false unless component

              if component.respond_to?(:scroll_up)
                component.scroll_up
              else
                component.handle_key(Adapters::Input::KeyDefinitions::NAVIGATION[:up].first)
              end
              true
            rescue StandardError
              false
            end

            def scroll_down
              if setup_mode?
                key = Adapters::Input::KeyDefinitions::NAVIGATION[:down].first
                return !!dispatch_key(key)
              end

              component = active_component
              return false unless component

              if component.respond_to?(:scroll_down)
                content_height = component.instance_variable_get(:@last_content_height) || 10
                lines = Array(component.instance_variable_get(:@formatted_lines))
                max_scroll = [lines.length - content_height, 0].max
                component.scroll_down(max_scroll)
              else
                component.handle_key(Adapters::Input::KeyDefinitions::NAVIGATION[:down].first)
              end
              true
            rescue StandardError
              false
            end

            def setup_mode?
              popup = current_popup
              popup_visible? && popup.respond_to?(:setup_mode?) && popup.setup_mode?
            rescue StandardError
              false
            end

            def fuzzy_mode?
              component = active_component
              component.respond_to?(:fuzzy_mode?) && component.fuzzy_mode?
            rescue StandardError
              false
            end

            def toggle_fuzzy(matches = nil)
              component = active_component
              return false unless component&.respond_to?(:toggle_fuzzy)

              component.toggle_fuzzy(matches)
              true
            rescue StandardError
              false
            end

            def next_entry
              component = active_component
              return false unless component&.respond_to?(:next_entry)

              component.next_entry
            rescue StandardError
              false
            end

            def prepare_setup_popup
              !!ensure_setup_popup
            rescue StandardError
              false
            end

            def show_setup(**kwargs)
              popup = ensure_setup_popup
              return false unless popup&.respond_to?(:show_setup)

              popup.show_setup(**kwargs)
              true
            rescue StandardError
              false
            end

            def update_setup(**kwargs)
              popup = ensure_setup_popup
              return false unless popup&.respond_to?(:update_setup)

              popup.update_setup(**kwargs)
              true
            rescue StandardError
              false
            end

            private

            def ensure_setup_popup
              popup = current_popup || @ui_component_factory&.dictionary_popup
              return nil unless popup

              current_panel&.hide
              @state_writer.update_reader(
                dictionary_panel: nil,
                dictionary_popup: popup,
                dictionary_visible: true,
                mode: :dictionary,
                popup_menu: nil
              )
              popup
            end

            def active_component
              return current_panel if panel_visible?
              return current_popup if popup_visible?

              nil
            end

            def current_panel
              @reader_state_reader&.dictionary_panel
            rescue StandardError
              nil
            end

            def current_popup
              @reader_state_reader&.dictionary_popup
            rescue StandardError
              nil
            end

            def component_visible?(component)
              component.respond_to?(:visible?) && component.visible?
            rescue StandardError
              false
            end

            def dispatch_key(key)
              component = active_component
              return nil unless component&.respond_to?(:handle_key)

              component.handle_key(key)
            rescue StandardError
              nil
            end
          end
        end
      end
    end
  end
end
