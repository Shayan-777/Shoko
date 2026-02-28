# frozen_string_literal: true

require_relative 'sidebar/toc_navigation'
require_relative 'sidebar/anchor_resolver'
require_relative 'sidebar/tab_state_orchestrator'
require_relative 'sidebar/toc_facade'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinates sidebar interactions while delegating focused logic to collaborators.
        class SidebarController
          Dependencies = Data.define(
            :reader_state,
            :config_reader,
            :ui_state,
            :sidebar_state,
            :state_writer,
            :document,
            :navigation_service,
            :bookmark_service,
            :state_controller,
            :ui_controller,
            :notification_service,
            :formatting_service,
            :layout_service
          ) do
            REQUIRED_FIELDS = %i[
              reader_state
              config_reader
              ui_state
              sidebar_state
              state_writer
            ].freeze

            def validate!
              missing = REQUIRED_FIELDS.select { |field| public_send(field).nil? }
              return self if missing.empty?

              raise ArgumentError, "Missing required sidebar controller dependencies: #{missing.join(', ')}"
            end
          end

          include Sidebar::TocFacade

          def initialize(deps:)
            deps.validate!

            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @ui_state = deps.ui_state
            @sidebar_state = deps.sidebar_state
            @state_writer = deps.state_writer
            @document = deps.document
            @navigation_service = deps.navigation_service
            @bookmark_service = deps.bookmark_service
            @state_controller = deps.state_controller
            @ui_controller = deps.ui_controller
            @notification_service = deps.notification_service
            @formatting_service = deps.formatting_service
            @layout_service = deps.layout_service

            @toc_navigation = Sidebar::TocNavigation.new
            @anchor_resolver = Sidebar::AnchorResolver.new(
              document_reader: -> { @document },
              formatting_service: @formatting_service,
              layout_service: @layout_service,
              ui_state_reader: @ui_state,
              config_reader: @config_reader,
              sidebar_state_reader: @sidebar_state
            )
            @tab_state_orchestrator = Sidebar::TabStateOrchestrator.new(
              config_reader: @config_reader,
              reader_state_reader: @reader_state,
              sidebar_state_reader: @sidebar_state,
              state_writer: @state_writer,
              toc_navigation: @toc_navigation,
              document_reader: -> { @document },
              ui_controller: @ui_controller,
              notification_service: @notification_service
            )
          end

          def open_toc
            @tab_state_orchestrator.open_toc
          end

          def open_bookmarks
            @tab_state_orchestrator.open_bookmarks
          end

          def open_annotations_tab
            @tab_state_orchestrator.open_annotations_tab
          end

          def activate_sidebar_tab(tab)
            @tab_state_orchestrator.activate_sidebar_tab(tab)
          end

          def handle_sidebar_toc_click(index)
            return unless sidebar_visible?
            return unless index.is_a?(Integer)

            entries = toc_entries_for(@document)
            return if entries.empty?
            return unless index.between?(0, entries.length - 1)

            collapsed = toc_collapsed_for(entries)
            updates = { toc_selected: index }

            if !toc_filter_active? && toc_entry_has_children?(entries, index)
              collapsed = toggle_toc_collapsed(collapsed, index)
              updates[:toc_collapsed] = collapsed
              updates[:toc_selected] = ensure_visible_toc_selection(entries, collapsed, index)
            end

            @state_writer.update_sidebar(**updates)
          end

          def set_sidebar_toc_selected(index)
            return unless sidebar_visible?

            entries = toc_entries_for(@document)
            return if entries.empty?

            idx = index.to_i.clamp(0, entries.length - 1)
            collapsed = toc_collapsed_for(entries)
            idx = ensure_visible_toc_selection(entries, collapsed, idx)

            updates = { toc_selected: idx }
            updates[:toc_collapsed] = collapsed if collapsed != @sidebar_state.sidebar_toc_collapsed
            @state_writer.update_sidebar(**updates)
          end

          # Sidebar navigation helpers
          def sidebar_down
            update_sidebar_selection(+1)
          end

          def sidebar_up
            update_sidebar_selection(-1)
          end

          def sidebar_select
            return unless sidebar_visible?

            case @sidebar_state.sidebar_active_tab
            when :toc then sidebar_select_toc
            when :bookmarks then sidebar_select_bookmark
            when :annotations then sidebar_select_annotation
            end
          end

          def sidebar_toggle_toc
            return unless sidebar_visible?
            return unless @sidebar_state.sidebar_active_tab == :toc
            return if toc_filter_active?

            entries = toc_entries_for(@document)
            return if entries.empty?

            idx = (@sidebar_state.sidebar_toc_selected || 0).to_i
            return unless idx.between?(0, entries.length - 1)
            return unless toc_entry_has_children?(entries, idx)

            collapsed = toc_collapsed_for(entries)
            collapsed = toggle_toc_collapsed(collapsed, idx)
            selected = ensure_visible_toc_selection(entries, collapsed, idx)

            @state_writer.update_sidebar(
              toc_collapsed: collapsed,
              toc_selected: selected
            )
          end

          def sidebar_visible?
            @tab_state_orchestrator.sidebar_visible?
          end

          def close_sidebar_with_restore(tab)
            @tab_state_orchestrator.close_sidebar_with_restore(tab)
          end

          private

          def sidebar_select_toc
            entries = toc_entries_for(@document)
            selected_entry_index = (@sidebar_state.sidebar_toc_selected || 0).to_i
            selected_entry_index = selected_entry_index.clamp(0, [entries.length - 1, 0].max)
            selected_entry_index = ensure_visible_toc_selection(
              entries,
              toc_collapsed_for(entries),
              selected_entry_index
            )
            entry = entries[selected_entry_index]
            return unless entry

            chapter_index = entry.chapter_index
            return unless chapter_index

            line_offset = line_offset_for_toc_entry(entry, chapter_index)
            if line_offset && @state_controller.respond_to?(:jump_to_chapter_offset)
              @state_controller.jump_to_chapter_offset(chapter_index, line_offset)
            else
              @navigation_service&.jump_to_chapter(chapter_index)
            end
            close_sidebar_with_restore(:toc)
          end

          def sidebar_select_bookmark
            bookmarks = @reader_state.bookmarks || []
            selected = (@sidebar_state.sidebar_bookmarks_selected || 0).to_i
            selected = selected.clamp(0, [bookmarks.length - 1, 0].max)
            bookmark = bookmarks[selected]
            return unless bookmark

            if @bookmark_service
              @bookmark_service.jump_to_bookmark(bookmark)
              @state_controller&.save_progress
            end
            close_sidebar_with_restore(:bookmarks)
          end

          def sidebar_select_annotation
            annotations = @reader_state.annotations || []
            selected = (@sidebar_state.sidebar_annotations_selected || 0).to_i
            selected = selected.clamp(0, [annotations.length - 1, 0].max)
            annotation = annotations[selected]
            return unless annotation

            @state_controller&.jump_to_annotation(annotation)
            close_sidebar_with_restore(:annotations)
          end

          def update_sidebar_selection(delta)
            return unless sidebar_visible?

            case @sidebar_state.sidebar_active_tab
            when :toc then update_toc_selection(delta)
            when :annotations then update_list_selection(delta, :annotations, :sidebar_annotations_selected)
            when :bookmarks then update_list_selection(delta, :bookmarks, :sidebar_bookmarks_selected)
            end
          end

          def update_toc_selection(delta)
            entries = toc_entries_for(@document)
            raw_collapsed = @sidebar_state.sidebar_toc_collapsed
            collapsed = toc_collapsed_for(entries, raw_collapsed)
            indices = navigable_toc_entry_indices(entries, collapsed)

            cur = (@sidebar_state.sidebar_toc_selected || indices.first || 0).to_i
            cur = ensure_visible_toc_selection(entries, collapsed, cur)
            target = find_toc_target(indices, cur, delta)

            updates = { toc_selected: target }
            updates[:toc_collapsed] = collapsed if raw_collapsed != collapsed
            @state_writer.update_sidebar(**updates)
          end

          def find_toc_target(indices, current, delta)
            @toc_navigation.target_index(indices, current, delta)
          end

          def update_list_selection(delta, list_key, state_key)
            items = sidebar_list_items(list_key)
            current = sidebar_list_selection(state_key)
            max = [items.length - 1, 0].max
            new_val = (current + delta).clamp(0, max)

            action_key = state_key.to_s.sub('sidebar_', '').to_sym
            @state_writer.update_sidebar(action_key => new_val)
          end

          def sidebar_list_items(list_key)
            case list_key
            when :annotations
              @reader_state.annotations || []
            when :bookmarks
              @reader_state.bookmarks || []
            else
              []
            end
          rescue StandardError
            []
          end

          def sidebar_list_selection(state_key)
            case state_key
            when :sidebar_annotations_selected
              @sidebar_state.sidebar_annotations_selected || 0
            when :sidebar_bookmarks_selected
              @sidebar_state.sidebar_bookmarks_selected || 0
            else
              0
            end
          rescue StandardError
            0
          end

          def line_offset_for_toc_entry(entry, chapter_index)
            @anchor_resolver.line_offset_for_toc_entry(entry, chapter_index)
          end
        end
      end
    end
  end
end
