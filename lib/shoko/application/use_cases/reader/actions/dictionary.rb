# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require 'shoko/shared/text_sanitizer'
require 'shoko/core/services/text_buffer_edit'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes dictionary intents. Query and selection edits write the reader
          # view-state directly (the definition popup re-renders from that state);
          # confirm submits-vs-defines exactly as the bar would. Surface lifecycle,
          # the lookup itself, and language/fuzzy coordination stay behind the
          # control port (adapter/service-bound). Mirrors Reader::Actions::Search.
          class Dictionary
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              open_dictionary
              close_dictionary
              edit_reader_dictionary_query
              dictionary_confirm
              dictionary_move_up
              dictionary_move_down
              dictionary_cycle_result
              dictionary_cycle_pair
              dictionary_swap_languages
              dictionary_toggle_fuzzy
            ].freeze

            def initialize(reader_dictionary_control:, reader_view_state_store:, reader_view_mutator:)
              @reader_dictionary_control = reader_dictionary_control
              @reader_view_state_store = reader_view_state_store
              @reader_view_mutator = reader_view_mutator
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader dictionary intent')
            end

            private

            def routes
              @routes ||= dictionary_visibility_routes
                          .merge(dictionary_text_routes)
                          .merge(dictionary_selection_routes)
                          .merge(dictionary_command_routes)
                          .freeze
            end

            def supported_payloads
              nil_payloads(
                :close_dictionary,
                :dictionary_confirm,
                :dictionary_cycle_result,
                :dictionary_cycle_pair,
                :dictionary_swap_languages,
                :dictionary_toggle_fuzzy
              )
                .merge(open_dictionary: [Hash, NilClass])
                .merge(edit_op_payloads(:edit_reader_dictionary_query))
                .merge(delta_payloads(:dictionary_move_up, :dictionary_move_down))
                .freeze
            end

            def dictionary_visibility_routes
              {
                open_dictionary: route(payload: :raw, result: :handled) do |context|
                  @reader_dictionary_control.open_dictionary_lookup(context)
                end,
              }
                .merge(handled_routes(:close_dictionary) { @reader_dictionary_control.close_dictionary_lookup })
            end

            def dictionary_text_routes
              {
                edit_reader_dictionary_query: route(payload: :edit_op, result: :handled) do |op|
                  apply_dictionary_edit(op)
                end,
              }
            end

            def dictionary_selection_routes
              route_map_for(
                %i[dictionary_move_up dictionary_move_down],
                payload: :delta,
                result: :handled
              ) do |delta|
                move_selection(delta)
              end
            end

            def dictionary_command_routes
              handled_routes(:dictionary_confirm) { confirm_dictionary }
                .merge(handled_routes(:dictionary_cycle_result) { cycle_result })
                .merge(handled_routes(:dictionary_cycle_pair) { @reader_dictionary_control.cycle_dictionary_pair })
                .merge(handled_routes(:dictionary_swap_languages) do
                  @reader_dictionary_control.swap_dictionary_languages
                end)
                .merge(handled_routes(:dictionary_toggle_fuzzy) do
                  @reader_dictionary_control.toggle_dictionary_fuzzy_matching
                end)
            end

            # During the first-run install wizard the bar's keys drive the wizard's
            # own language-code input (a centered overlay), not the lookup query.
            def cycle_result
              return @reader_dictionary_control.apply_dictionary_setup if setup_active?

              @reader_dictionary_control.cycle_dictionary_result
            end

            def apply_dictionary_edit(operation)
              return @reader_dictionary_control.edit_dictionary_setup(operation) if setup_active?

              case operation.operation
              when :insert    then insert_query_text(operation.text)
              when :backspace then write_query(without_last_grapheme(view_snapshot.dictionary_query))
              end
            end

            def without_last_grapheme(query)
              text = query.to_s
              Shoko::Core::Services::TextBufferEdit.backspace_at(text, text.length).first
            end

            def setup_active?
              view_snapshot.dictionary_setup_active == true
            end

            def insert_query_text(text)
              return unless Shoko::Shared::TextSanitizer.printable_char?(text.to_s)

              write_query("#{view_snapshot.dictionary_query}#{text}")
            end

            def write_query(text)
              @reader_view_mutator.update_reader(dictionary_query: text.to_s)
            end

            # Mirrors the bar's confirm: submit when the query changed since the
            # last lookup; otherwise, in fuzzy mode, define the selected candidate;
            # otherwise it is already defined (no-op).
            def confirm_dictionary
              return @reader_dictionary_control.confirm_dictionary_setup if setup_active?

              snapshot = view_snapshot
              if query_stale?(snapshot)
                @reader_dictionary_control.submit_dictionary_lookup
              elsif snapshot.dictionary_fuzzy_mode == true
                define_selected_candidate(snapshot)
              end
            end

            def define_selected_candidate(snapshot)
              matches = Array(snapshot.dictionary_fuzzy_matches)
              return if matches.empty?

              candidate = matches[snapshot.dictionary_selected_index.to_i.clamp(0, matches.length - 1)]
              @reader_view_mutator.update_reader(dictionary_query: candidate.word.to_s)
              @reader_dictionary_control.submit_dictionary_lookup
            end

            def move_selection(delta)
              return @reader_dictionary_control.move_dictionary_setup(delta: delta) if setup_active?

              snapshot = view_snapshot
              index = next_selection_index(snapshot, delta)
              @reader_view_mutator.update_reader(dictionary_selected_index: index)
            end

            # In fuzzy mode the index selects a candidate (clamped to the list);
            # otherwise it scrolls the definition card (the component caps the top).
            def next_selection_index(snapshot, delta)
              current = snapshot.dictionary_selected_index.to_i
              return [current + delta.to_i, 0].max unless snapshot.dictionary_fuzzy_mode == true

              matches = Array(snapshot.dictionary_fuzzy_matches)
              return 0 if matches.empty?

              (current + delta.to_i).clamp(0, matches.length - 1)
            end

            def query_stale?(snapshot)
              snapshot.dictionary_query.to_s.strip != snapshot.dictionary_results_query.to_s.strip
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
