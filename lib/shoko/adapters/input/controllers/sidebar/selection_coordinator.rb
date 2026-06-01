# frozen_string_literal: true



module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          # Owns sidebar TOC/list selection, activation, and navigation updates.
          class SelectionCoordinator
            # Builds dependency records for the sidebar selection coordinator.
            module DependencyBuilder
              def build(**kwargs)
                new(**kwargs.slice(*members))
              end
            end

            # Validates the selection coordinator dependency records before use.
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
              assign_state_dependencies(state)
              assign_toc_dependencies(toc)
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


            def handle_toc_click(index, document:)
              return unless sidebar_visible?
              return unless index.is_a?(Integer)

              entries = toc_entries_for(document)
              return if entries.empty?
              return unless index.between?(0, entries.length - 1)

              collapsed = toc_collapsed_for(entries)
              updates = { toc_selected: index }

              if !toc_filter_active? && toc_entry_has_children?(entries, index)
                collapsed = toggle_toc_collapsed(collapsed, index, entries)
                updates[:toc_collapsed] = collapsed
                updates[:toc_selected] = ensure_visible_toc_selection(entries, collapsed, index)
              end

              @reader_session_mutator.update_sidebar(**updates)
            end

            def set_toc_selected(index, document:)
              return unless sidebar_visible?

              entries = toc_entries_for(document)
              return if entries.empty?

              selected = index.to_i.clamp(0, entries.length - 1)
              collapsed = toc_collapsed_for(entries)
              selected = ensure_visible_toc_selection(entries, collapsed, selected)

              updates = { toc_selected: selected }
              updates[:toc_collapsed] = collapsed if collapsed != @sidebar_state.sidebar_toc_collapsed
              @reader_session_mutator.update_sidebar(**updates)
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

            def assign_state_dependencies(state)
              @reader_state = state.reader_state_reader
              @sidebar_state = state.sidebar_state_reader
              @reader_session_mutator = state.reader_session_mutator
              @navigation_service = state.navigation_service
              @bookmark_service = state.bookmark_service
              @state_controller = state.state_controller
              @close_sidebar = state.close_sidebar
              @sidebar_visible = state.sidebar_visible
            end

            def assign_toc_dependencies(toc)
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


            def select_bookmark
              bookmark = select_list_item(@reader_state.bookmarks, @sidebar_state.sidebar_bookmarks_selected)
              return unless bookmark

              if @bookmark_service
                @bookmark_service.jump_to_bookmark(bookmark)
                @state_controller&.save_progress
              end
              @close_sidebar.call(:bookmarks)
            end

            def select_annotation
              annotation = select_list_item(@reader_state.annotations, @sidebar_state.sidebar_annotations_selected)
              return unless annotation

              @state_controller&.jump_to_annotation(annotation)
              @close_sidebar.call(:annotations)
            end

            def select_list_item(items, raw_index)
              items = Array(items)
              selected = (raw_index || 0).to_i.clamp(0, [items.length - 1, 0].max)
              items[selected]
            end

            def move_list(delta, list_key, state_key)
              items = sidebar_list_items(list_key)
              current = sidebar_list_selection(state_key)
              new_val = (current + delta).clamp(0, [items.length - 1, 0].max)

              @reader_session_mutator.update_sidebar(state_key.to_s.sub('sidebar_', '').to_sym => new_val)
            end

            def sidebar_list_items(list_key)
              case list_key
              when :annotations then @reader_state.annotations || []
              when :bookmarks then @reader_state.bookmarks || []
              else []
              end
            end

            def sidebar_list_selection(state_key)
              case state_key
              when :sidebar_annotations_selected then @sidebar_state.sidebar_annotations_selected || 0
              when :sidebar_bookmarks_selected then @sidebar_state.sidebar_bookmarks_selected || 0
              else 0
              end
            end


            def select_toc(document)
              entries = toc_entries_for(document)
              selected = (@sidebar_state.sidebar_toc_selected || 0).to_i
              selected = selected.clamp(0, [entries.length - 1, 0].max)
              selected = ensure_visible_toc_selection(entries, toc_collapsed_for(entries), selected)
              entry = entries[selected]
              return unless entry

              chapter_index = entry.chapter_index
              return unless chapter_index

              line_offset = @line_offset_for_toc_entry.call(entry, chapter_index)
              if line_offset
                @state_controller.jump_to_chapter_offset(chapter_index, line_offset)
              else
                @navigation_service&.jump_to_chapter(chapter_index)
              end
              @close_sidebar.call(:toc)
            end

            def move_toc(delta, document)
              entries = toc_entries_for(document)
              raw_collapsed = @sidebar_state.sidebar_toc_collapsed
              collapsed = toc_collapsed_for(entries, raw_collapsed)
              indices = navigable_toc_entry_indices(entries, collapsed)

              current = (@sidebar_state.sidebar_toc_selected || indices.first || 0).to_i
              current = ensure_visible_toc_selection(entries, collapsed, current)
              target = @find_toc_target.call(indices, current, delta)

              updates = { toc_selected: target }
              updates[:toc_collapsed] = collapsed if raw_collapsed != collapsed
              @reader_session_mutator.update_sidebar(**updates)
            end

          end
        end
      end
    end
  end
end
