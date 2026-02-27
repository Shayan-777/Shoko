# frozen_string_literal: true

require_relative 'base_action'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Actions
          # Generic action for updating state fields under a namespace.
          # This consolidates the common pattern of updating fields in a specific
          # state namespace (reader, menu, config, ui).
          #
          # @example Updating reader state
          #   state.dispatch(UpdateStateAction.new(:reader, bookmarks: [...], current_chapter: 5))
          #
          # @example Updating config state
          #   state.dispatch(UpdateStateAction.new(:config, theme: :dark, view_mode: :single))
          #
          # @example Updating with allowed fields filter
          #   state.dispatch(UpdateStateAction.new(:reader,
          #     { page_map: [...], total_pages: 100 },
          #     allowed: [:page_map, :total_pages, :last_width, :last_height]
          #   ))
          class UpdateStateAction < BaseAction
            # @param namespace [Symbol] The state namespace (:reader, :menu, :config, :ui)
            # @param updates [Hash] Hash of field => value updates
            # @param allowed [Array<Symbol>, nil] Optional allowlist of fields. If provided,
            #   only these fields will be updated.
            def initialize(namespace, updates = {}, allowed: nil)
              super(namespace: namespace, updates: updates, allowed: allowed)
            end

            def apply(state)
              namespace = payload[:namespace]
              updates = payload[:updates]
              allowed = payload[:allowed]

              state_updates = {}
              updates.each do |field, value|
                next if allowed && !allowed.include?(field)

                state_updates[[namespace, field]] = value
              end

              state.update(state_updates) unless state_updates.empty?
            end
          end

          # Convenience classes for common namespaces - these provide a cleaner API
          # while using UpdateStateAction internally.

          # Action for updating reader state fields
          #
          # @example
          #   state.dispatch(UpdateReaderAction.new(current_chapter: 5, bookmarks: [...]))
          class UpdateReaderAction < UpdateStateAction
            def initialize(allowed: nil, **updates)
              super(:reader, updates, allowed: allowed)
            end
          end

          # Action for updating UI state fields
          #
          # @example
          #   state.dispatch(UpdateUIAction.new(loading_active: true, loading_message: 'Loading...'))
          class UpdateUIAction < UpdateStateAction
            def initialize(allowed: nil, **updates)
              super(:ui, updates, allowed: allowed)
            end
          end
        end
      end
    end
  end
end
