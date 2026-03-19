# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          class SelectionCoordinator
            # Handles TOC-specific click, selection, and navigation flows.
            module TocFlow
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
end
