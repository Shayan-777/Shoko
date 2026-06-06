# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes Table-of-Contents mode intents. The TOC panel is an overlay reader
          # mode (a sibling of in-book search and the dictionary card), so the bottom
          # bar becomes a "TOC" filter input while the panel lists chapters above it.
          #
          # Filtering, selection movement, and activation all need the document's TOC
          # tree, so — unlike search, which edits its query in the use case — these
          # delegate to the control port (adapter/document-bound).
          class Toc
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              open_toc
              close_toc
              edit_toc_filter
              toc_confirm
              toc_move_up
              toc_move_down
            ].freeze

            def initialize(reader_toc_control:)
              @reader_toc_control = reader_toc_control
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader toc intent')
            end

            private

            def routes
              @routes ||= {
                open_toc: route(result: :handled) { @reader_toc_control.open_toc_lookup },
                close_toc: route(result: :handled) { @reader_toc_control.close_toc_lookup },
                edit_toc_filter: route(payload: :edit_op, result: :handled) do |op|
                  @reader_toc_control.edit_toc_filter(op)
                end,
                toc_confirm: route(result: :handled) { @reader_toc_control.activate_toc_selection },
                toc_move_up: route(payload: :delta, result: :handled) do |delta|
                  @reader_toc_control.move_toc_selection(delta)
                end,
                toc_move_down: route(payload: :delta, result: :handled) do |delta|
                  @reader_toc_control.move_toc_selection(delta)
                end,
              }.freeze
            end

            def supported_payloads
              {
                open_toc: [NilClass],
                close_toc: [NilClass],
                edit_toc_filter: [Shoko::Application::UseCases::Requests::EditOp],
                toc_confirm: [NilClass],
                toc_move_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                toc_move_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
              }
            end
          end
        end
      end
    end
  end
end
