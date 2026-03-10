# frozen_string_literal: true

require_relative 'selection_coordinator/list_flow'
require_relative 'selection_coordinator/toc_flow'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          # Owns sidebar TOC/list selection, activation, and navigation updates.
          class SelectionCoordinator
            include ListFlow
            include TocFlow

            module DependencyBuilder
              def build(**kwargs)
                new(**kwargs.slice(*members))
              end
            end

            module Validation
              def validate!
                missing = Array(self.class.required_fields).select { |field| public_send(field).nil? }
                return self if missing.empty?

                raise ArgumentError, "Missing required #{self.class.name.split('::').last}: #{missing.join(', ')}"
              end
            end

            StateDependencies = Data.define(
              :reader_state_reader,
              :sidebar_state_reader,
              :reader_session_mutator,
              :navigation_service,
              :bookmark_service,
              :state_controller,
              :close_sidebar,
              :sidebar_visible
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[reader_state_reader sidebar_state_reader reader_session_mutator close_sidebar sidebar_visible]
              end
            end

            TocDependencies = Data.define(
              :toc_entries_for,
              :toc_collapsed_for,
              :toc_filter_active,
              :toc_entry_has_children,
              :ensure_visible_toc_selection,
              :navigable_toc_entry_indices,
              :find_toc_target,
              :toggle_toc_collapsed,
              :line_offset_for_toc_entry
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                members
              end
            end

            def initialize(state:, toc:)
              state.validate!
              toc.validate!

              @reader_state = state.reader_state_reader
              @sidebar_state = state.sidebar_state_reader
              @reader_session_mutator = state.reader_session_mutator
              @navigation_service = state.navigation_service
              @bookmark_service = state.bookmark_service
              @state_controller = state.state_controller
              @close_sidebar = state.close_sidebar
              @sidebar_visible = state.sidebar_visible
              @toc_entries_for = toc.toc_entries_for
              @toc_collapsed_for = toc.toc_collapsed_for
              @toc_filter_active = toc.toc_filter_active
              @toc_entry_has_children = toc.toc_entry_has_children
              @ensure_visible_toc_selection = toc.ensure_visible_toc_selection
              @navigable_toc_entry_indices = toc.navigable_toc_entry_indices
              @find_toc_target = toc.find_toc_target
              @toggle_toc_collapsed = toc.toggle_toc_collapsed
              @line_offset_for_toc_entry = toc.line_offset_for_toc_entry
            end

            def select(document:)
              return unless sidebar_visible?

              case @sidebar_state.sidebar_active_tab
              when :toc then select_toc(document)
              when :bookmarks then select_bookmark
              when :annotations then select_annotation
              end
            end

            def move(delta, document:)
              return unless sidebar_visible?

              case @sidebar_state.sidebar_active_tab
              when :toc then move_toc(delta, document)
              when :annotations then move_list(delta, :annotations, :sidebar_annotations_selected)
              when :bookmarks then move_list(delta, :bookmarks, :sidebar_bookmarks_selected)
              end
            end

            def toggle_toc(document:)
              return unless sidebar_visible?
              return unless @sidebar_state.sidebar_active_tab == :toc
              return if toc_filter_active?

              entries = toc_entries_for(document)
              return if entries.empty?

              selected = (@sidebar_state.sidebar_toc_selected || 0).to_i
              return unless selected.between?(0, entries.length - 1)
              return unless toc_entry_has_children?(entries, selected)

              collapsed = toggle_toc_collapsed(toc_collapsed_for(entries), selected, entries)
              @reader_session_mutator.update_sidebar(
                toc_collapsed: collapsed,
                toc_selected: ensure_visible_toc_selection(entries, collapsed, selected)
              )
            end

            private

            def sidebar_visible?
              @sidebar_visible.call
            end

            def toc_entries_for(document)
              @toc_entries_for.call(document)
            end

            def toc_collapsed_for(entries, raw = nil)
              @toc_collapsed_for.call(entries, raw)
            end

            def toc_filter_active?
              @toc_filter_active.call
            end

            def toc_entry_has_children?(entries, index)
              @toc_entry_has_children.call(entries, index)
            end

            def ensure_visible_toc_selection(entries, collapsed, current)
              @ensure_visible_toc_selection.call(entries, collapsed, current)
            end

            def navigable_toc_entry_indices(entries, collapsed)
              @navigable_toc_entry_indices.call(entries, collapsed)
            end

            def toggle_toc_collapsed(collapsed, index, entries)
              return collapsed unless toc_entry_has_children?(entries, index)

              @toggle_toc_collapsed.call(collapsed, index)
            end
          end
        end
      end
    end
  end
end
