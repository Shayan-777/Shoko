# frozen_string_literal: true

require_relative '../../../../core/ports/in_book_search_ui_session'
require_relative '../../../input/key_definitions'

module Shoko
  module Adapters
    module Output
      module Ui
        module Sessions
          # Adapter-owned lifecycle for in-book search popup component.
          class InBookSearchUiSessionAdapter
            include Core::Ports::InBookSearchUiSession

            def initialize(reader_state_reader:, state_writer:, ui_component_factory:)
              @reader_state_reader = reader_state_reader
              @state_writer = state_writer
              @ui_component_factory = ui_component_factory
            end

            def open(query: '', results: [], total_matches: 0)
              popup = ensure_popup
              return false unless popup

              popup.show(query: query, results: results, total_matches: total_matches)
              @state_writer.update_reader(
                in_book_search_popup: popup,
                mode: :in_book_search,
                popup_menu: nil
              )
              true
            rescue StandardError
              false
            end

            def close
              current_popup&.hide
              @state_writer.update_reader(
                in_book_search_popup: nil,
                mode: :read
              )
              true
            rescue StandardError
              false
            end

            def visible?
              popup = current_popup
              popup.respond_to?(:visible?) && popup.visible?
            rescue StandardError
              false
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

            def scroll_up
              popup = current_popup
              return false unless popup

              popup.handle_key(Adapters::Input::KeyDefinitions::NAVIGATION[:up].first)
              true
            rescue StandardError
              false
            end

            def scroll_down
              popup = current_popup
              return false unless popup

              popup.handle_key(Adapters::Input::KeyDefinitions::NAVIGATION[:down].first)
              true
            rescue StandardError
              false
            end

            def update(query:, results:, total_matches:, results_query:)
              popup = current_popup
              return false unless popup&.respond_to?(:update)

              popup.update(
                query: query,
                results: results,
                total_matches: total_matches,
                results_query: results_query
              )
              true
            rescue StandardError
              false
            end

            private

            def ensure_popup
              current_popup || @ui_component_factory&.in_book_search_popup
            rescue StandardError
              nil
            end

            def current_popup
              @reader_state_reader&.in_book_search_popup
            rescue StandardError
              nil
            end

            def dispatch_key(key)
              popup = current_popup
              return nil unless popup&.respond_to?(:handle_key)

              popup.handle_key(key)
            rescue StandardError
              nil
            end
          end
        end
      end
    end
  end
end
