# frozen_string_literal: true

require 'cgi'
require_relative '../../core/services/config_bridge'

module Shoko
  module Application::Controllers
    # Handles all sidebar-related functionality: TOC, bookmarks, annotations tabs
    class SidebarController
      def initialize(reader_state:, config_reader:, ui_state:, sidebar_state:, state_writer:,
                     document: nil, navigation_service: nil, bookmark_service: nil,
                     state_controller: nil, ui_controller: nil, notification_service: nil,
                     formatting_service: nil, layout_service: nil)
        @reader_state = reader_state
        @config_reader = config_reader
        @ui_state = ui_state
        @sidebar_state = sidebar_state
        @state_writer = state_writer
        @document = document
        @navigation_service = navigation_service
        @bookmark_service = bookmark_service
        @state_controller = state_controller
        @ui_controller = ui_controller
        @notification_service = notification_service
        @formatting_service = formatting_service
        @layout_service = layout_service
      end

      # Setter injection for circular dependency resolution — set after construction
      attr_writer :state_controller

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

        doc = @document
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

        @state_writer.update_sidebar(**updates)
      end

      def set_sidebar_toc_selected(index)
        return unless sidebar_visible?

        doc = @document
        entries = toc_entries_for(doc)
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

        doc = @document
        entries = toc_entries_for(doc)
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
        @sidebar_state.sidebar_visible?
      end

      def close_sidebar_with_restore(tab)
        prev_mode = @sidebar_state.sidebar_prev_view_mode
        if prev_mode
          @state_writer.update_config(view_mode: prev_mode)
          @state_writer.update_selections(sidebar_prev_view_mode: nil)
        end
        @state_writer.update_sidebar(visible: false)
        @state_writer.update_reader(mode: :read)
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
        raw = @sidebar_state.sidebar_toc_collapsed if raw.nil?
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
        @sidebar_state.sidebar_visible? &&
          @sidebar_state.sidebar_active_tab == tab
      end

      def open_sidebar_for(tab)
        # Store current view and force single-page view
        @state_writer.update_selections(
          sidebar_prev_view_mode: @config_reader.view_mode
        )
        @state_writer.update_config(view_mode: :single)

        updates = { active_tab: tab, visible: true }
        case tab
        when :toc
          doc = @document
          entries = toc_entries_for(doc)
          collapsed = toc_collapsed_for(entries)
          current_chapter = (@reader_state.current_chapter || 0).to_i
          selected = toc_index_for_chapter(entries, current_chapter)
          updates[:toc_collapsed] = collapsed
          updates[:toc_selected] = ensure_visible_toc_selection(entries, collapsed, selected)
        when :annotations
          updates[:annotations_selected] =
            @sidebar_state.sidebar_annotations_selected || 0
        when :bookmarks
          updates[:bookmarks_selected] =
            @sidebar_state.sidebar_bookmarks_selected || 0
        end

        @state_writer.update_sidebar(**updates)
        @state_writer.update_reader(mode: :read)
        set_message("#{tab.to_s.capitalize} opened", 1) unless tab == :toc
      end

      def switch_sidebar_tab(tab)
        return unless sidebar_visible?

        current_tab = @sidebar_state.sidebar_active_tab
        return if current_tab == tab

        updates = { active_tab: tab }
        case tab
        when :toc
          doc = @document
          entries = toc_entries_for(doc)
          collapsed = toc_collapsed_for(entries)
          selected = @sidebar_state.sidebar_toc_selected
          if selected.nil?
            current_chapter = (@reader_state.current_chapter || 0).to_i
            selected = toc_index_for_chapter(entries, current_chapter)
          end
          updates[:toc_collapsed] = collapsed
          updates[:toc_selected] = ensure_visible_toc_selection(entries, collapsed, selected)
        when :annotations
          updates[:annotations_selected] = @sidebar_state.sidebar_annotations_selected || 0
        when :bookmarks
          updates[:bookmarks_selected] = @sidebar_state.sidebar_bookmarks_selected || 0
        end

        @state_writer.update_sidebar(**updates)
      end

      def sidebar_select_toc
        doc = @document
        entries = toc_entries_for(doc)
        selected_entry_index = (@sidebar_state.sidebar_toc_selected || 0).to_i
        selected_entry_index = selected_entry_index.clamp(0, [entries.length - 1, 0].max)
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
        doc = @document
        entries = toc_entries_for(doc)
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
        return current if delta.zero?

        search_indices, fallback = delta.positive? ? [indices, indices.last] : [indices.reverse, indices.first]
        search_indices.find { |idx| delta.positive? ? idx > current : idx < current } || fallback || current
      end

      def update_list_selection(delta, list_key, state_key)
        items = @reader_state.send(list_key) || []
        current = @sidebar_state.send(state_key) || 0
        max = [items.length - 1, 0].max
        new_val = (current + delta).clamp(0, max)

        action_key = state_key.to_s.sub('sidebar_', '').to_sym
        @state_writer.update_sidebar(action_key => new_val)
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

      def set_message(text, _duration = 2)
        @notification_service&.set_message(nil, text, _duration)
      rescue StandardError
        @state_writer.update_reader(message: text)
      end

      def close_annotations_overlay_via_ui_controller
        @ui_controller&.close_annotations_overlay
      rescue StandardError
        # Best effort
      end

      def line_offset_for_toc_entry(entry, chapter_index)
        anchor = anchor_from_href(entry&.href)
        return nil if anchor.nil? || anchor.empty?

        lines = wrapped_lines_for_anchor(chapter_index)
        return nil if lines.nil? || lines.empty?

        anchor_down = anchor.downcase
        lines.each_with_index do |line, idx|
          next unless line.respond_to?(:metadata)

          anchors = line.metadata[:anchors] || line.metadata['anchors']
          next unless anchors

          anchors = Array(anchors).map(&:to_s)
          return idx if anchors.include?(anchor)
          return idx if anchors.any? { |value| value.casecmp?(anchor) }
          return idx if anchors.any? { |value| value.downcase == anchor_down }
        end
        nil
      rescue StandardError
        nil
      end

      def wrapped_lines_for_anchor(chapter_index)
        return nil unless @formatting_service && @layout_service && @document

        width = (@ui_state.terminal_width || 80).to_i
        height = (@ui_state.terminal_height || 24).to_i
        view_mode = @config_reader.view_mode
        line_spacing = @config_reader.line_spacing
        col_width, content_height = @layout_service.calculate_metrics(width, height, view_mode)
        lines_per_page = @layout_service.adjust_for_line_spacing(content_height, line_spacing)

        config_bridge = @config_reader ? Shoko::Core::Services::ConfigBridge.new(@config_reader) : nil
        @formatting_service.wrap_all(@document, chapter_index, col_width,
                                     config: config_bridge, lines_per_page: lines_per_page)
      rescue StandardError
        nil
      end

      def anchor_from_href(href)
        return nil if href.nil?

        fragment = href.to_s.split('#', 2)[1]
        return nil if fragment.nil? || fragment.empty?

        CGI.unescape(fragment.to_s).strip
      rescue StandardError
        nil
      end
    end
  end
end
