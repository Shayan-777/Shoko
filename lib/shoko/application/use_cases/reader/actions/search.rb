# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require 'shoko/shared/text_sanitizer'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes in-book search intents. Query and selection edits write the
          # reader view-state directly (the popup component re-renders from that
          # state); confirm dispatches submit-vs-open exactly as the popup did.
          # Surface lifecycle, search execution, and result navigation stay
          # behind the control port (adapter/document-bound).
          class Search
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              open_in_book_search
              close_in_book_search
              edit_in_book_search
              search_confirm
              search_move_up
              search_move_down
            ].freeze

            def initialize(reader_search_control:, reader_view_state_store:, reader_view_mutator:)
              @reader_search_control = reader_search_control
              @reader_view_state_store = reader_view_state_store
              @reader_view_mutator = reader_view_mutator
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader search intent')
            end

            private

            def routes
              @routes ||= {
                open_in_book_search: route(result: :handled) { @reader_search_control.open_search_session },
                close_in_book_search: route(result: :handled) { @reader_search_control.close_search_session },
                edit_in_book_search: route(payload: :edit_op, result: :handled) do |op|
                  apply_search_edit(op)
                end,
                search_confirm: route(result: :handled) { confirm_search },
                search_move_up: route(payload: :delta, result: :handled) do |delta|
                  move_selection(delta)
                end,
                search_move_down: route(payload: :delta, result: :handled) do |delta|
                  move_selection(delta)
                end,
              }.freeze
            end

            def supported_payloads
              {
                open_in_book_search: [NilClass],
                close_in_book_search: [NilClass],
                edit_in_book_search: [Shoko::Application::UseCases::Requests::EditOp],
                search_confirm: [NilClass],
                search_move_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                search_move_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
              }
            end

            def apply_search_edit(op)
              case op.operation
              when :insert    then insert_query_text(op.text)
              when :backspace then write_query(view_snapshot.search_query.to_s[0...-1].to_s)
              end
            end

            def insert_query_text(text)
              return unless Shoko::Shared::TextSanitizer.printable_char?(text.to_s)

              write_query("#{view_snapshot.search_query}#{text}")
            end

            def write_query(text)
              @reader_view_mutator.update_reader(search_query: text.to_s)
            end

            # Mirrors InBookSearchPopupComponent#confirm: submit when the query has
            # changed since the last search; otherwise open the selected result;
            # otherwise (no results — empty query, or a settled zero-result query)
            # re-submit.
            def confirm_search
              snapshot = view_snapshot
              if query_stale?(snapshot)
                @reader_search_control.submit_search_session
              elsif (selected = selected_result(snapshot))
                @reader_search_control.open_search_result(selected)
              else
                @reader_search_control.submit_search_session
              end
            end

            def move_selection(delta)
              snapshot = view_snapshot
              results = Array(snapshot.search_results)
              return if results.empty?

              index = (snapshot.search_selected_index.to_i + delta.to_i).clamp(0, results.length - 1)
              @reader_view_mutator.update_reader(search_selected_index: index)
            end

            def query_stale?(snapshot)
              snapshot.search_query.to_s.strip != snapshot.search_results_query.to_s.strip
            end

            def selected_result(snapshot)
              results = Array(snapshot.search_results)
              return nil if results.empty?

              results[snapshot.search_selected_index.to_i]
            end

            def view_snapshot
              @reader_view_state_store.load
            end
          end
        end
      end
    end
  end
end
