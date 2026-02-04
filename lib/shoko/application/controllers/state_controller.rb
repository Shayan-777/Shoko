# frozen_string_literal: true

module Shoko
  module Application::Controllers
    # Handles all state management: persistence, bookmarks, progress
    class StateController
      def initialize(state:, doc:, path:, terminal_service:,
                     progress_repository: nil, bookmark_repository: nil,
                     annotation_service: nil, logger: nil, navigation_service: nil,
                     page_calculator: nil, layout_service: nil, bookmark_service: nil,
                     notification_service: nil, coordinate_service: nil,
                     render_registry: nil)
        @state = state
        @doc = doc
        @path = path
        @terminal_service = terminal_service
        @progress_repository = progress_repository
        @bookmark_repository = bookmark_repository
        @annotation_service = annotation_service
        @logger = logger
        @navigation_service = navigation_service
        @page_calculator = page_calculator
        @layout_service = layout_service
        @bookmark_service = bookmark_service
        @notification_service = notification_service
        @coordinate_service = coordinate_service
        @render_registry = render_registry
      end

      def save_progress
        return unless @path && @doc

        progress_data = collect_progress_data
        canonical = canonical_path_for_doc

        @progress_repository.save_for_book(canonical,
                                           chapter_index: progress_data[:chapter],
                                           line_offset: progress_data[:line_offset])
      end

      def load_progress
        canonical = canonical_path_for_doc
        progress = @progress_repository.find_by_book_path(canonical)
        # Fallback: attempt original open path if canonical not found (for legacy records)
        progress = @progress_repository.find_by_book_path(@path) if !progress && @path != canonical
        return unless progress

        apply_progress_data(progress)
      end

      def load_bookmarks
        canonical = canonical_path_for_doc
        bookmarks = @bookmark_repository.find_by_book_path(canonical)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(bookmarks: bookmarks))
      end

      def add_bookmark
        if @bookmark_service
          @bookmark_service.add_bookmark
        else
          position = current_bookmark_position
          canonical = canonical_path_for_doc
          begin
            @bookmark_repository.add_for_book(canonical,
                                              chapter_index: position[:chapter],
                                              line_offset: position[:line_offset],
                                              text_snippet: '')
            bookmarks = @bookmark_repository.find_by_book_path(canonical)
          rescue StandardError
            bookmarks = @state.get(%i[reader bookmarks]) || []
          end
          @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(bookmarks: bookmarks))
        end

        curr_ch = @state.get(%i[reader current_chapter]) || 0
        curr_page = current_page_label
        set_message("Bookmark added at Chapter #{curr_ch + 1}, Page #{curr_page}")
      end

      def jump_to_bookmark
        bookmarks = bookmarks_list
        selected_idx = @state.get(%i[reader sidebar_bookmarks_selected]) || 0
        bookmark = bookmarks[selected_idx]
        return unless bookmark

        chapter_index = bookmark.chapter_index
        if @navigation_service
          @navigation_service.jump_to_chapter(chapter_index)
        else
          @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(current_chapter: chapter_index))
        end

        offset = bookmark.line_offset.to_i
        stride = split_stride_for_state
        payload = {
          single_page: offset,
          left_page: offset,
          right_page: offset + stride,
          current_page: offset,
        }

        if Shoko::Application::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && @page_calculator
          page_index = @page_calculator.find_page_index(chapter_index, offset)
          payload[:current_page_index] = page_index if page_index
        end

        @state.dispatch(Shoko::Application::Actions::UpdatePageAction.new(**payload))
        save_progress
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(mode: :read))
      end

      def delete_selected_bookmark
        bookmarks = bookmarks_list
        selected_idx = @state.get(%i[reader sidebar_bookmarks_selected]) || 0
        bookmark = bookmarks[selected_idx]
        return unless bookmark

        canonical = canonical_path_for_doc
        @bookmark_repository.delete_for_book(canonical, bookmark)
        load_bookmarks
        current_bookmarks = bookmarks_list
        max_selected = if current_bookmarks.any?
                         [selected_idx, current_bookmarks.length - 1].min
                       else
                         0
                       end
        @state.dispatch(
          Shoko::Application::Actions::UpdateSidebarAction.new(bookmarks_selected: max_selected)
        )
        set_message('Bookmark deleted!')
      end

      def refresh_annotations
        annotations = []
        begin
          annotations = @annotation_service ? @annotation_service.list_for_book(@path) : []
        rescue StandardError => e
          @logger&.error('Failed to refresh annotations', error: e.message, path: @path)
        ensure
          @state.dispatch(Application::Actions::UpdateReaderAction.new(annotations: annotations))
        end
      end

      def split_stride_for_state
        return 1 unless @layout_service

        width = @state.get(%i[ui terminal_width])
        height = @state.get(%i[ui terminal_height])
        height, width = @terminal_service.size if (!width || !height) && @terminal_service
        width = width.to_i
        height = height.to_i
        width = 80 if width <= 0
        height = 24 if height <= 0

        _, content_height = @layout_service.calculate_metrics(width, height, :split)
        spacing = @state.get(%i[config line_spacing]) || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
        stride = @layout_service.adjust_for_line_spacing(content_height, spacing)
        stride = 1 if stride.to_i <= 0
        stride
      rescue StandardError
        1
      end

      def current_bookmark_position
        chapter = @state.get(%i[reader current_chapter]) || 0
        if dynamic_page_numbering? && @page_calculator
          page_index = @state.get(%i[reader current_page_index]) || 0
          page = @page_calculator.get_page(page_index)
          if page
            chapter = page[:chapter_index] || chapter
            line = page[:start_line] || page['start_line']
            return { chapter: chapter, line_offset: line.to_i }
          end
        end

        view_mode = Application::Selectors::ConfigSelectors.view_mode(@state)
        line_offset = view_mode == :split ? @state.get(%i[reader left_page]) : @state.get(%i[reader single_page])
        { chapter: chapter, line_offset: line_offset || 0 }
      rescue StandardError
        { chapter: chapter, line_offset: 0 }
      end

      def current_page_label
        if dynamic_page_numbering?
          ((@state.get(%i[reader current_page_index]) || 0).to_i + 1)
        else
          @state.get(%i[reader current_page]) || 0
        end
      rescue StandardError
        0
      end

      def dynamic_page_numbering?
        Application::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic
      rescue StandardError
        false
      end

      def jump_to_annotation(annotation)
        normalized = normalize_annotation(annotation)
        return unless normalized

        chapter_index = normalized[:chapter_index]
        range = normalized[:range]
        @navigation_service&.jump_to_chapter(chapter_index) if chapter_index

        if range
          selection = normalize_selection_for_state(range)
          @state.dispatch(Shoko::Application::Actions::UpdateSelectionAction.new(selection)) if selection
        end

        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(mode: :read))
      end

      def jump_to_chapter_offset(chapter_index, line_offset)
        return unless chapter_index

        if @navigation_service
          @navigation_service.jump_to_chapter(chapter_index)
        else
          @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(current_chapter: chapter_index))
        end

        offset = line_offset.to_i
        stride = split_stride_for_state
        payload = {
          single_page: offset,
          left_page: offset,
          right_page: offset + stride,
          current_page: offset,
        }

        if dynamic_page_numbering? && @page_calculator
          page_index = @page_calculator.find_page_index(chapter_index, offset)
          payload[:current_page_index] = page_index if page_index
        end

        @state.dispatch(Shoko::Application::Actions::UpdatePageAction.new(**payload))
        save_progress
      rescue StandardError
        nil
      end

      def delete_annotation_by_id(annotation)
        current_index = @state.get(%i[reader sidebar_annotations_selected]) || 0
        normalized = normalize_annotation(annotation)
        annotation_id = normalized[:id]

        svc = @annotation_service
        return current_index unless svc && annotation_id

        svc.delete(@path, annotation_id)
        annotations = svc.list_for_book(@path)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotations: annotations))

        new_index = [current_index, annotations.length - 1].min
        new_index = 0 if new_index.negative?
        @state.dispatch(Shoko::Application::Actions::UpdateSidebarAction.new(
                          annotations_selected: new_index,
                          sidebar_annotations_selected: new_index
                        ))
        new_index
      rescue StandardError
        current_index
      end

      def quit_to_menu
        save_progress
        @state.dispatch(Shoko::Application::Actions::QuitToMenuAction.new)
      end

      def quit_application
        save_progress
        @terminal_service.cleanup
        exit 0
      end

      private

      private :split_stride_for_state

      def canonical_path_for_doc
        @doc.respond_to?(:canonical_path) ? @doc.canonical_path : @path
      end

      def normalize_selection_for_state(range)
        return nil unless range

        return range if anchor_range?(range)

        coord = resolve_coordinate_service
        return nil unless coord

        rendered = Shoko::Application::Selectors::ReaderSelectors.rendered_lines(
          @state, render_registry: @render_registry
        )
        coord.normalize_selection_range(range, rendered)
      rescue StandardError
        nil
      end

      def anchor_range?(range)
        return false unless range.is_a?(Hash)

        start_anchor = range[:start] || range['start']
        start_anchor.is_a?(Hash) && (start_anchor.key?(:geometry_key) || start_anchor.key?('geometry_key'))
      end

      def resolve_coordinate_service
        @coordinate_service
      end

      def bookmarks_list
        @state.get(%i[reader bookmarks])
      end

      def collect_progress_data
        if Application::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && @page_calculator
          collect_dynamic_progress(@page_calculator)
        else
          collect_absolute_progress
        end
      end

      def normalize_annotation(annotation)
        return {} unless annotation.is_a?(Hash)

        annotation.transform_keys do |key|
          key.is_a?(String) ? key.to_sym : key
        end
      end

      def collect_dynamic_progress(page_calculator)
        page_data = page_calculator.get_page(@state.get(%i[reader current_page_index]))
        return { chapter: 0, line_offset: 0 } unless page_data

        {
          chapter: page_data[:chapter_index],
          line_offset: page_data[:start_line],
        }
      end

      def collect_absolute_progress
        line_offset = if Application::Selectors::ConfigSelectors.view_mode(@state) == :split
                        @state.get(%i[reader left_page])
                      else
                        @state.get(%i[reader single_page])
                      end

        {
          chapter: @state.get(%i[reader current_chapter]),
          line_offset: line_offset,
        }
      end

      def apply_progress_data(progress)
        chapter = extract_chapter(progress)
        line_offset = extract_line_offset(progress)

        apply_chapter(chapter)
        apply_page_position(line_offset)
      end

      def extract_chapter(progress)
        if progress.respond_to?(:chapter_index)
          progress.chapter_index
        else
          progress['chapter'] || progress[:chapter] || 0
        end
      end

      def extract_line_offset(progress)
        if progress.respond_to?(:line_offset)
          progress.line_offset
        else
          progress['line_offset'] || progress[:line_offset] || 0
        end
      end

      def apply_chapter(chapter)
        valid_chapter = chapter >= @doc.chapter_count ? 0 : chapter
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(current_chapter: valid_chapter))
      end

      def apply_page_position(line_offset)
        if dynamic_page_mode?
          apply_dynamic_page_position(line_offset)
        else
          apply_absolute_page_position(line_offset)
        end
      end

      def dynamic_page_mode?
        Application::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && @page_calculator
      end

      def apply_dynamic_page_position(line_offset)
        estimate_and_set_page_index(line_offset)
        store_pending_progress(line_offset)
      end

      def estimate_and_set_page_index(line_offset)
        width  = (@state.get(%i[ui terminal_width]) || 80).to_i
        height = (@state.get(%i[ui terminal_height]) || 24).to_i
        layout = @layout_service
        _, content_height = layout.calculate_metrics(
          width, height, Application::Selectors::ConfigSelectors.view_mode(@state)
        )
        lines_per_page = layout.adjust_for_line_spacing(
          content_height, Application::Selectors::ConfigSelectors.line_spacing(@state)
        )
        est_index = lines_per_page.positive? ? (line_offset.to_f / lines_per_page).floor : 0
        @state.dispatch(Shoko::Application::Actions::UpdatePageAction.new(current_page_index: est_index))
      rescue StandardError
        # best-effort; leave index as-is if estimation fails
      end

      def store_pending_progress(line_offset)
        @state.dispatch(Shoko::Application::Actions::UpdateSelectionsAction.new(
                          pending_progress: {
                            chapter_index: @state.get(%i[reader current_chapter]),
                            line_offset: line_offset,
                          }
                        ))
      end

      def apply_absolute_page_position(line_offset)
        @state.dispatch(Shoko::Application::Actions::UpdatePageAction.new(
                          single_page: line_offset, left_page: line_offset
                        ))
      end

      def set_message(text, duration = 2)
        if @notification_service
          @notification_service.set_message(@state, text, duration)
        else
          @state.dispatch(Shoko::Application::Actions::UpdateMessageAction.new(text))
        end
      rescue StandardError
        @state.dispatch(Shoko::Application::Actions::UpdateMessageAction.new(text))
      end
    end
  end
end
