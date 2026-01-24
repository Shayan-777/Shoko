# frozen_string_literal: true

module Shoko
  module Application::Controllers
    # Handles all sidebar-related functionality: TOC, bookmarks, annotations tabs
    class SidebarController
      def initialize(state, dependencies)
        @state = state
        @dependencies = dependencies
      end

      def open_toc
        toggle_sidebar(:toc)
      rescue StandardError => e
        set_message("TOC error: #{e.message}", 3)
      end

      def open_bookmarks
        toggle_sidebar(:bookmarks)
      end

      def open_annotations_tab
        toggle_sidebar(:annotations)
      end

      def activate_sidebar_tab(tab)
        if sidebar_visible?
          switch_sidebar_tab(tab)
        else
          open_sidebar_for(tab)
        end
      rescue StandardError => e
        set_message("Sidebar error: #{e.message}", 3)
      end

      def handle_sidebar_toc_click(index)
        return unless sidebar_visible?
        return unless index.is_a?(Integer)

        doc = safe_resolve(:document)
        entries = toc_entries_for(doc)
        return if entries.empty?
        return unless index.between?(0, entries.length - 1)

        collapsed = toc_collapsed_for(entries)
        updates = { toc_selected: index }

        if toc_entry_has_children?(entries, index)
          collapsed = toggle_toc_collapsed(collapsed, index)
          updates[:toc_collapsed] = collapsed
          updates[:toc_selected] = ensure_visible_toc_selection(entries, collapsed, index)
        end

        @state.dispatch(Shoko::Application::Actions::UpdateSidebarAction.new(**updates))
      end

      def set_sidebar_toc_selected(index)
        return unless sidebar_visible?

        doc = safe_resolve(:document)
        entries = toc_entries_for(doc)
        return if entries.empty?

        idx = index.to_i.clamp(0, entries.length - 1)
        collapsed = toc_collapsed_for(entries)
        idx = ensure_visible_toc_selection(entries, collapsed, idx)

        updates = { toc_selected: idx }
        updates[:toc_collapsed] = collapsed if collapsed != @state.get(%i[reader sidebar_toc_collapsed])
        @state.dispatch(Shoko::Application::Actions::UpdateSidebarAction.new(**updates))
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

        case @state.get(%i[reader sidebar_active_tab])
        when :toc then sidebar_select_toc
        when :bookmarks then sidebar_select_bookmark
        when :annotations then sidebar_select_annotation
        end
      end

      def sidebar_visible?
        @state.get(%i[reader sidebar_visible])
      end

      def close_sidebar_with_restore(tab)
        prev_mode = @state.get(%i[reader sidebar_prev_view_mode])
        if prev_mode
          @state.dispatch(
            Shoko::Application::Actions::UpdateConfigAction.new(view_mode: prev_mode)
          )
          @state.dispatch(
            Shoko::Application::Actions::UpdateSelectionsAction.new(sidebar_prev_view_mode: nil)
          )
        end
        @state.dispatch(Shoko::Application::Actions::UpdateSidebarAction.new(visible: false))
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(mode: :read))
        set_message("#{tab.to_s.capitalize} closed", 1) unless tab == :toc
      end

      # TOC helpers exposed for external use
      def toc_entries_for(doc)
        entries = doc.respond_to?(:toc_entries) ? Array(doc.toc_entries) : []
        return entries unless entries.empty?

        chapters = doc.respond_to?(:chapters) ? Array(doc.chapters) : []
        chapters.each_with_index.map do |chapter, idx|
          title = chapter.respond_to?(:title) ? chapter.title.to_s : ''
          title = "Chapter #{idx + 1}" if title.strip.empty?
          Core::Models::TOCEntry.new(
            title: title,
            href: nil,
            level: 0,
            chapter_index: idx,
            navigable: true
          )
        end
      end

      def toc_collapsed_for(entries, raw = nil)
        raw = @state.get(%i[reader sidebar_toc_collapsed]) if raw.nil?
        entries = Array(entries)
        return [] if entries.empty?
        return default_toc_collapsed(entries) if raw.nil?

        normalize_toc_collapsed(entries, raw)
      end

      def toc_visible_indices(entries, collapsed)
        entries = Array(entries)
        return [] if entries.empty?

        collapsed_set = Array(collapsed).each_with_object({}) { |idx, memo| memo[idx] = true }
        visible = []
        skip_levels = []

        entries.each_with_index do |entry, idx|
          level = entry.level
          skip_levels.pop while skip_levels.any? && level <= skip_levels.last
          next if skip_levels.any?

          visible << idx
          next unless collapsed_set[idx]
          next unless toc_entry_has_children?(entries, idx)

          skip_levels << level
        end

        visible
      end

      def toc_entry_has_children?(entries, index)
        next_entry = entries[index + 1]
        next_entry && next_entry.level > entries[index].level
      end

      private

      # Unified sidebar toggling for :toc, :annotations, :bookmarks
      def toggle_sidebar(tab)
        close_annotations_overlay_via_ui_controller
        if sidebar_visible?
          return close_sidebar_with_restore(tab) if sidebar_open_for?(tab)

          switch_sidebar_tab(tab)
        else
          open_sidebar_for(tab)
        end
      end

      def sidebar_open_for?(tab)
        @state.get(%i[reader sidebar_visible]) &&
          @state.get(%i[reader sidebar_active_tab]) == tab
      end

      def open_sidebar_for(tab)
        # Store current view and force single-page view
        @state.dispatch(
          Shoko::Application::Actions::UpdateSelectionsAction.new(
            sidebar_prev_view_mode: @state.get(%i[config view_mode])
          )
        )
        @state.dispatch(
          Shoko::Application::Actions::UpdateConfigAction.new(view_mode: :single)
        )

        updates = { active_tab: tab, visible: true }
        case tab
        when :toc
          doc = safe_resolve(:document)
          entries = toc_entries_for(doc)
          collapsed = toc_collapsed_for(entries)
          current_chapter = (@state.get(%i[reader current_chapter]) || 0).to_i
          selected = toc_index_for_chapter(entries, current_chapter)
          updates[:toc_collapsed] = collapsed
          updates[:toc_selected] = ensure_visible_toc_selection(entries, collapsed, selected)
        when :annotations
          updates[:annotations_selected] =
            @state.get(%i[reader sidebar_annotations_selected]) || 0
        when :bookmarks
          updates[:bookmarks_selected] =
            @state.get(%i[reader sidebar_bookmarks_selected]) || 0
        end

        @state.dispatch(Shoko::Application::Actions::UpdateSidebarAction.new(**updates))
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(mode: :read))
        set_message("#{tab.to_s.capitalize} opened", 1) unless tab == :toc
      end

      def switch_sidebar_tab(tab)
        return unless sidebar_visible?

        current_tab = @state.get(%i[reader sidebar_active_tab])
        return if current_tab == tab

        updates = { active_tab: tab }
        case tab
        when :toc
          doc = safe_resolve(:document)
          entries = toc_entries_for(doc)
          collapsed = toc_collapsed_for(entries)
          selected = @state.get(%i[reader sidebar_toc_selected])
          if selected.nil?
            current_chapter = (@state.get(%i[reader current_chapter]) || 0).to_i
            selected = toc_index_for_chapter(entries, current_chapter)
          end
          updates[:toc_collapsed] = collapsed
          updates[:toc_selected] = ensure_visible_toc_selection(entries, collapsed, selected)
        when :annotations
          updates[:annotations_selected] = @state.get(%i[reader sidebar_annotations_selected]) || 0
        when :bookmarks
          updates[:bookmarks_selected] = @state.get(%i[reader sidebar_bookmarks_selected]) || 0
        end

        @state.dispatch(Shoko::Application::Actions::UpdateSidebarAction.new(**updates))
      end

      def sidebar_select_toc
        doc = safe_resolve(:document)
        entries = toc_entries_for(doc)
        selected_entry_index = (@state.get(%i[reader sidebar_toc_selected]) || 0).to_i
        selected_entry_index = selected_entry_index.clamp(0, [entries.length - 1, 0].max)
        chapter_index = entries[selected_entry_index]&.chapter_index
        return unless chapter_index

        nav_service = @dependencies.resolve(:navigation_service)
        nav_service.jump_to_chapter(chapter_index)
        close_sidebar_with_restore(:toc)
      end

      def sidebar_select_bookmark
        bookmarks = @state.get(%i[reader bookmarks]) || []
        selected = (@state.get(%i[reader sidebar_bookmarks_selected]) || 0).to_i
        selected = selected.clamp(0, [bookmarks.length - 1, 0].max)
        bookmark = bookmarks[selected]
        return unless bookmark

        bookmark_service = safe_resolve(:bookmark_service)
        if bookmark_service
          bookmark_service.jump_to_bookmark(bookmark)
          safe_resolve(:state_controller)&.save_progress
        end
        close_sidebar_with_restore(:bookmarks)
      end

      def sidebar_select_annotation
        annotations = @state.get(%i[reader annotations]) || []
        selected = (@state.get(%i[reader sidebar_annotations_selected]) || 0).to_i
        selected = selected.clamp(0, [annotations.length - 1, 0].max)
        annotation = annotations[selected]
        return unless annotation

        state_controller = safe_resolve(:state_controller)
        state_controller&.jump_to_annotation(annotation)
        close_sidebar_with_restore(:annotations)
      end

      def update_sidebar_selection(delta)
        return unless sidebar_visible?

        case @state.get(%i[reader sidebar_active_tab])
        when :toc then update_toc_selection(delta)
        when :annotations then update_list_selection(delta, :annotations, :sidebar_annotations_selected)
        when :bookmarks then update_list_selection(delta, :bookmarks, :sidebar_bookmarks_selected)
        end
      end

      def update_toc_selection(delta)
        doc = safe_resolve(:document)
        entries = toc_entries_for(doc)
        raw_collapsed = @state.get(%i[reader sidebar_toc_collapsed])
        collapsed = toc_collapsed_for(entries, raw_collapsed)
        indices = navigable_toc_entry_indices(entries, collapsed)

        cur = (@state.get(%i[reader sidebar_toc_selected]) || indices.first || 0).to_i
        cur = ensure_visible_toc_selection(entries, collapsed, cur)
        target = find_toc_target(indices, cur, delta)

        updates = { toc_selected: target }
        updates[:toc_collapsed] = collapsed if raw_collapsed != collapsed
        @state.dispatch(Shoko::Application::Actions::UpdateSidebarAction.new(**updates))
      end

      def find_toc_target(indices, current, delta)
        return current if delta.zero?

        search_indices, fallback = delta.positive? ? [indices, indices.last] : [indices.reverse, indices.first]
        search_indices.find { |idx| delta.positive? ? idx > current : idx < current } || fallback || current
      end

      def update_list_selection(delta, list_key, state_key)
        items = @state.get([:reader, list_key]) || []
        current = @state.get([:reader, state_key]) || 0
        max = [items.length - 1, 0].max
        new_val = (current + delta).clamp(0, max)

        action_key = state_key.to_s.sub('sidebar_', '').to_sym
        @state.dispatch(Shoko::Application::Actions::UpdateSidebarAction.new(action_key => new_val))
      end

      def toggle_toc_collapsed(collapsed, index)
        list = Array(collapsed).dup
        if list.include?(index)
          list.delete(index)
        else
          list << index
        end
        list
      end

      def ensure_visible_toc_selection(entries, collapsed, current)
        visible = toc_visible_indices(entries, collapsed)
        return current if visible.include?(current)
        return visible.first || 0 if visible.empty?

        current_level = entries[current]&.level
        if current_level
          visible_set = visible.each_with_object({}) { |idx, memo| memo[idx] = true }
          (current - 1).downto(0) do |idx|
            next unless visible_set[idx]
            return idx if entries[idx].level < current_level
          end
        end

        visible.reverse.find { |idx| idx < current } || visible.first
      end

      def default_toc_collapsed(entries)
        entries.each_index.select { |idx| toc_entry_has_children?(entries, idx) }
      end

      def normalize_toc_collapsed(entries, raw)
        max_index = entries.length - 1
        Array(raw).map(&:to_i).uniq.select do |idx|
          idx.between?(0, max_index) && toc_entry_has_children?(entries, idx)
        end
      end

      def navigable_toc_entry_indices(entries, collapsed)
        visible = toc_visible_indices(entries, collapsed)
        indices = visible.select { |idx| entries[idx]&.chapter_index }
        return indices unless indices.empty?

        visible
      end

      def toc_index_for_chapter(entries, chapter_index)
        Array(entries).find_index { |entry| entry&.chapter_index == chapter_index } || 0
      end

      def safe_resolve(name)
        @dependencies.resolve(name)
      rescue StandardError
        nil
      end

      def set_message(text, duration = 2)
        notifier = @dependencies.resolve(:notification_service)
        notifier.set_message(@state, text, duration)
      rescue StandardError
        @state.dispatch(Shoko::Application::Actions::UpdateMessageAction.new(text))
      end

      def close_annotations_overlay_via_ui_controller
        ui_controller = safe_resolve(:ui_controller)
        ui_controller&.close_annotations_overlay
      rescue StandardError
        # Best effort
      end
    end
  end
end
