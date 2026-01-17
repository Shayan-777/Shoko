# frozen_string_literal: true

require_relative '../../adapters/output/ui/components/annotations_overlay_component'
require_relative '../../adapters/output/ui/components/annotation_editor_overlay_component'

module Shoko
  module Application::Controllers
    # Handles all UI-related functionality: modes, overlays, popups, sidebar
    class UIController
      # Raised when required dependencies are missing for a UI action.
      class MissingDependencyError < StandardError; end

      # Builds the annotation editor screen component for annotation editor mode.
      class AnnotationEditorMode
        def initialize(controller, dependencies)
          @controller = controller
          @dependencies = dependencies
        end

        def build_component(**)
          Shoko::Adapters::Output::Ui::Components::Screens::AnnotationEditorScreenComponent.new(
            @controller,
            **,
            dependencies: @dependencies
          )
        end
      end

      def initialize(state, dependencies)
        @state = state
        @dependencies = dependencies
        @current_mode = nil
      end

      def switch_mode(mode, **)
        annotation_editor_mode =
          mode == :annotation_editor ? AnnotationEditorMode.new(self, @dependencies) : nil
        close_annotations_overlay unless annotation_editor_mode
        close_annotation_editor_overlay unless annotation_editor_mode
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(mode: mode))

        # Rendered via screen/sidebar components; no standalone mode component
        @current_mode = annotation_editor_mode&.build_component(**)

        # Keep input dispatcher in sync with mode to prevent cross-mode key leaks
        begin
          input_controller = @dependencies.resolve(:input_controller)
          input_controller.activate_for_mode(mode) if input_controller.respond_to?(:activate_for_mode)
        rescue StandardError
          # If not available, ignore; read mode remains default
        end
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

      def open_annotations
        overlay = Application::Selectors::ReaderSelectors.annotations_overlay(@state)
        if overlay&.visible?
          close_annotations_overlay
        else
          show_annotations_overlay
        end
      end

      def open_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
        show_annotation_editor_overlay(text: text,
                                       range: range,
                                       chapter_index: chapter_index,
                                       annotation: annotation)
      end

      private

      # Unified sidebar toggling for :toc, :annotations, :bookmarks
      def toggle_sidebar(tab)
        close_annotations_overlay
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

      public

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

      def show_help
        switch_mode(:help)
      end

      def toggle_view_mode
        @state.dispatch(Shoko::Application::Actions::ToggleViewModeAction.new)
      end

      def increase_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@state.get(%i[config line_spacing])) || 1
        return unless current < 2

        @state.dispatch(Shoko::Application::Actions::UpdateConfigAction.new(line_spacing: modes[current + 1]))
        @state.dispatch(Shoko::Application::Actions::UpdatePageAction.new(last_width: 0))
      end

      def decrease_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@state.get(%i[config line_spacing])) || 1
        return unless current.positive?

        @state.dispatch(Shoko::Application::Actions::UpdateConfigAction.new(line_spacing: modes[current - 1]))
        @state.dispatch(Shoko::Application::Actions::UpdatePageAction.new(last_width: 0))
      end

      def toggle_page_numbering_mode
        current_mode = @state.get(%i[config page_numbering_mode])
        new_mode = current_mode == :absolute ? :dynamic : :absolute
        @state.dispatch(Shoko::Application::Actions::UpdateConfigAction.new(page_numbering_mode: new_mode))
        set_message("Page numbering: #{new_mode}")
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

      def handle_popup_action(action_data)
        # Handle both old string-based actions and new action objects
        action_type = action_data.is_a?(Hash) ? action_data[:action] : action_data

        case action_type
        when :create_annotation, 'Create Annotation'
          handle_create_annotation_action(action_data)
        when :copy_to_clipboard, 'Copy to Clipboard'
          handle_copy_to_clipboard_action(action_data)
        end

        skip_editor = %i[create_annotation].include?(action_type) || action_type == 'Create Annotation'
        cleanup_popup_state(skip_editor: skip_editor)
      end

      def cleanup_popup_state(skip_editor: false)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(popup_menu: nil))
        @state.dispatch(Shoko::Application::Actions::ClearSelectionAction.new)
        close_annotations_overlay
        close_annotation_editor_overlay unless skip_editor
        # Also reset any mouse-driven selection held outside state (MouseableReader)
        begin
          reader_controller = @dependencies.resolve(:reader_controller)
          reader_controller&.send(:clear_selection!)
        rescue StandardError
          # Best-effort; ignore if not available
        end
      end

      # Refresh annotations from persistence into state
      def refresh_annotations
        state_controller = @dependencies.resolve(:state_controller)
        state_controller.refresh_annotations if state_controller.respond_to?(:refresh_annotations)
      rescue StandardError
        # Best-effort; ignore failures silently here
      end

      # Provide current book path for modes/components that need persistence context
      def current_book_path
        @state.get(%i[reader book_path])
      end

      def set_message(text, duration = 2)
        notifier = @dependencies.resolve(:notification_service)
        notifier.set_message(@state, text, duration)
      rescue StandardError
        # Fallback to direct dispatch if service not available
        @state.dispatch(Shoko::Application::Actions::UpdateMessageAction.new(text))
      end

      attr_reader :current_mode

      private

      def sidebar_visible?
        @state.get(%i[reader sidebar_visible])
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

      def show_annotations_overlay
        overlay = Shoko::Adapters::Output::Ui::Components::AnnotationsOverlayComponent.new(@state)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotations_overlay: overlay))
        set_message('Annotations overlay open (↑/↓ navigate, Enter open, e edit, d delete)', 3)
      rescue StandardError
        cleanup_annotations_overlay_fallback
      end

      def close_annotations_overlay
        overlay = Application::Selectors::ReaderSelectors.annotations_overlay(@state)
        return unless overlay

        overlay.hide if overlay.respond_to?(:hide)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotations_overlay: nil))
      rescue StandardError
        cleanup_annotations_overlay_fallback
      end

      def show_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
        message = 'Annotation editor unavailable'
        overlay = Shoko::Adapters::Output::Ui::Components::AnnotationEditorOverlayComponent.new(
          selected_text: text,
          range: range,
          chapter_index: chapter_index,
          annotation: annotation
        )
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotation_editor_overlay: overlay))
        if activate_annotation_editor_overlay_session
          message = 'Annotation editor active (Ctrl+S save, Esc cancel)'
        else
          cleanup_annotation_editor_overlay_fallback
        end
      rescue StandardError => e
        cleanup_annotation_editor_overlay_fallback
        log_dependency_error(:show_annotation_editor_overlay, e)
      ensure
        set_message(message, 3)
      end

      def close_annotation_editor_overlay
        overlay = Application::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
        return unless overlay

        overlay.hide if overlay.respond_to?(:hide)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotation_editor_overlay: nil))
        deactivate_annotation_editor_overlay_session
      rescue StandardError
        cleanup_annotation_editor_overlay_fallback
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

      def default_toc_collapsed(entries)
        entries.each_index.select { |idx| toc_entry_has_children?(entries, idx) }
      end

      def normalize_toc_collapsed(entries, raw)
        max_index = entries.length - 1
        Array(raw).map(&:to_i).uniq.select do |idx|
          idx.between?(0, max_index) && toc_entry_has_children?(entries, idx)
        end
      end

      def toc_entry_has_children?(entries, index)
        next_entry = entries[index + 1]
        next_entry && next_entry.level > entries[index].level
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

      def handle_create_annotation_action(action_data)
        selection_range = if action_data.is_a?(Hash)
                            action_data[:data][:selection_range]
                          else
                            @state.get(%i[
                                         reader selection
                                       ])
                          end
        # Extract selected text from the controller that manages it
        selected_text = extract_selected_text_from_selection(selection_range)
        close_annotations_overlay
        show_annotation_editor_overlay(text: selected_text,
                                       range: selection_range,
                                       chapter_index: @state.get(%i[reader current_chapter]))
      end

      def handle_copy_to_clipboard_action(_action_data)
        clipboard_service = @dependencies.resolve(:clipboard_service)
        # Get selected text from current selection
        selection = @state.get(%i[reader selection])
        selected_text = extract_selected_text_from_selection(selection)

        if clipboard_service.available? && selected_text && !selected_text.strip.empty?
          success = clipboard_service.copy_with_feedback(selected_text) do |msg|
            set_message(msg)
          end
          set_message(' Failed to copy to clipboard') unless success
        else
          set_message(' Copy to clipboard not available')
        end
        switch_mode(:read)
      end

      # Extract selected text from selection range using SelectionService
      def extract_selected_text_from_selection(selection_range)
        selection_service = @dependencies.resolve(:selection_service)
        rendered_content_reader = @dependencies.resolve(:rendered_content_reader)
        if selection_service.respond_to?(:extract_from_state)
          selection_service.extract_from_state(@state, rendered_content_reader: rendered_content_reader, selection_range: selection_range)
        else
          rendered_lines = rendered_content_reader.rendered_lines
          selection_service.extract_text(selection_range, rendered_lines)
        end
      end

      def open_annotation_from_overlay(annotation)
        with_normalized_annotation(annotation) do |normalized|
          state_controller = @dependencies.resolve(:state_controller)
          state_controller.jump_to_annotation(normalized) if state_controller.respond_to?(:jump_to_annotation)
          close_annotations_overlay
        end
      rescue StandardError
        close_annotations_overlay
      end

      def edit_annotation_from_overlay(annotation)
        with_normalized_annotation(annotation) do |normalized|
          close_annotations_overlay
          show_annotation_editor_overlay(text: normalized[:text],
                                         range: normalized[:range],
                                         chapter_index: normalized[:chapter_index],
                                         annotation: normalized)
        end
      end

      def delete_annotation_from_overlay(annotation)
        with_normalized_annotation(annotation) do |normalized|
          state_controller = @dependencies.resolve(:state_controller)
          new_index = if state_controller.respond_to?(:delete_annotation_by_id)
                        state_controller.delete_annotation_by_id(normalized)
                      end

          overlay = Application::Selectors::ReaderSelectors.annotations_overlay(@state)
          overlay.selected_index = new_index if overlay.respond_to?(:selected_index=) && !new_index.nil?

          annotations = @state.get(%i[reader annotations]) || []
          close_annotations_overlay if annotations.empty?
          set_message('Annotation deleted', 2)
        end
      rescue StandardError
        close_annotations_overlay
      end

      def cleanup_annotations_overlay_fallback
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotations_overlay: nil))
      rescue StandardError
        nil
      end

      def normalize_annotation(annotation)
        return nil unless annotation.is_a?(Hash)

        annotation.transform_keys do |key|
          key.is_a?(String) ? key.to_sym : key
        end
      end

      def with_normalized_annotation(annotation)
        normalized = normalize_annotation(annotation)
        return unless normalized

        yield normalized
      end

      def cleanup_annotation_editor_overlay_fallback
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotation_editor_overlay: nil))
        deactivate_annotation_editor_overlay_session
      rescue StandardError
        nil
      end

      def handle_annotation_editor_overlay_event(result)
        overlay = Application::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
        return unless overlay

        case result[:type]
        when :save
          save_annotation_from_overlay(result[:note], overlay)
        when :cancel
          cancel_annotation_editor_overlay
        end
      end

      def save_annotation_from_overlay(note, overlay)
        svc = @dependencies.resolve(:annotation_service)
        path = current_book_path
        unless svc && path
          cancel_annotation_editor_overlay
          return
        end

        begin
          if overlay.annotation_id
            svc.update(path, overlay.annotation_id, note)
            set_message('Annotation updated', 2)
          else
            svc.add(path, overlay.selected_text, note, overlay.selection_range, overlay.chapter_index, nil)
            set_message('Annotation saved!', 2)
          end
          refresh_annotations
        rescue StandardError => e
          set_message("Save failed: #{e.message}", 3)
        ensure
          close_annotation_editor_overlay
          @state.dispatch(Shoko::Application::Actions::ClearSelectionAction.new)
        end
      end

      def cancel_annotation_editor_overlay
        close_annotation_editor_overlay
        set_message('Annotation cancelled', 2)
        @state.dispatch(Shoko::Application::Actions::ClearSelectionAction.new)
      end

      def activate_annotation_editor_overlay_session
        reader_controller = resolve_required(:reader_controller)
        input_controller = resolve_required(:input_controller)
        reader_controller.activate_annotation_editor_overlay_session
        input_controller.enter_modal_mode(:annotation_editor)
        true
      rescue MissingDependencyError => e
        log_dependency_error(:activate_annotation_editor_overlay_session, e)
        false
      end

      def deactivate_annotation_editor_overlay_session
        input_controller = resolve_optional(:input_controller)
        input_controller&.exit_modal_mode(:annotation_editor)
        reader_controller = resolve_optional(:reader_controller)
        reader_controller&.deactivate_annotation_editor_overlay_session
      end

      def resolve_required(key)
        service = @dependencies.resolve(key)
        raise MissingDependencyError, "Dependency :#{key} not registered" unless service

        service
      rescue MissingDependencyError
        raise
      rescue StandardError => e
        raise MissingDependencyError, "Dependency :#{key} failed to resolve: #{e.message}"
      end

      def resolve_optional(key)
        @dependencies.resolve(key)
      rescue StandardError
        nil
      end

      def log_dependency_error(context, error)
        logger = resolve_optional(:logger)
        return unless logger.respond_to?(:error)

        logger.error('Annotation editor activation failed', context: context, error: error.message)
      rescue StandardError
        nil
      end
    end
  end
end
