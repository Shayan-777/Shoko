# frozen_string_literal: true

require_relative 'dependencies/state_controller_dependencies'
require_relative 'support/message_notifier'
require_relative '../../../core/models/reading_progress'
require_relative '../../../core/models/reader_settings'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles all state management: persistence, bookmarks, progress.
        class StateController
          Dependencies = Shoko::Adapters::Input::Controllers::Dependencies::StateControllerDependencies::Bundle

          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

          def initialize(deps:)
            dependencies = deps.validate!
            assign_session_dependencies(dependencies.session)
            assign_document_dependencies(dependencies.document)
            assign_service_dependencies(dependencies.services)
          end


          def save_progress
            return unless @path && current_doc

            progress_data = collect_progress_data
            canonical = canonical_path_for_doc

            @progress_repository.save_for_book(canonical,
                                               chapter_index: progress_data[:chapter],
                                               line_offset: progress_data[:line_offset])
          end

          def load_progress
            canonical = canonical_path_for_doc
            progress = @progress_repository.find_by_book_path(canonical)
            return unless progress

            apply_progress_data(progress)
          end

          def quit_to_menu
            save_progress
            @reader_session_mutator.quit_to_menu
          end

          def quit_application
            save_progress
            @terminal_service.cleanup
            @process_control&.terminate(0)
          end


          def load_bookmarks
            canonical = canonical_path_for_doc
            bookmarks = @bookmark_repository.find_by_book_path(canonical)
            @reader_session_mutator.update_reader(bookmarks: bookmarks)
          end

          def add_bookmark
            persist_bookmark
            set_message("Bookmark added at Chapter #{current_chapter_label}, Page #{current_page_label}")
          end

          def jump_to_bookmark
            bookmark = selected_bookmark
            return unless bookmark

            chapter_index = bookmark.chapter_index
            jump_to_bookmark_chapter(chapter_index)
            apply_bookmark_position(chapter_index, bookmark.line_offset.to_i)
          end

          def delete_selected_bookmark
            bookmarks = bookmarks_list
            selected_idx = @sidebar_state.sidebar_bookmarks_selected || 0
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
            @reader_session_mutator.update_sidebar(bookmarks_selected: max_selected)
            set_message('Bookmark deleted!')
          end


          def refresh_annotations
            annotations = []
            begin
              annotations = @annotation_service ? @annotation_service.list_for_book(@path) : []
            rescue Shoko::Error => e
              @logger&.error('Failed to refresh annotations', error: e.message, path: @path)
            ensure
              @reader_session_mutator.update_reader(annotations: annotations)
            end
          end

          def jump_to_annotation(annotation)
            normalized = normalize_annotation(annotation)
            return unless normalized

            chapter_index = normalized[:chapter_index]
            range = normalized[:range]
            @navigation_service&.jump_to_chapter(chapter_index) if chapter_index

            if range
              selection = normalize_selection_for_state(range)
              @reader_session_mutator.update_reader(selection: selection) if selection
            end

            @reader_session_mutator.update_reader(mode: :read)
          end

          def jump_to_chapter_offset(chapter_index, line_offset)
            return unless chapter_index

            if @navigation_service
              @navigation_service.jump_to_chapter(chapter_index)
            else
              @reader_session_mutator.update_reader(current_chapter: chapter_index)
            end

            offset = line_offset.to_i
            stride = split_stride_for_state
            payload = { single_page: offset, left_page: offset, right_page: offset + stride, current_page: offset }

            if dynamic_page_numbering? && @page_calculator
              page_index = @page_calculator.find_page_index(chapter_index, offset)
              payload[:current_page_index] = page_index if page_index
            end

            @reader_session_mutator.update_reader(**payload)
            save_progress
          end

          def delete_annotation_by_id(annotation)
            current_index = @sidebar_state.sidebar_annotations_selected || 0
            normalized = normalize_annotation(annotation)
            annotation_id = normalized[:id]

            svc = @annotation_service
            return current_index unless svc && annotation_id

            svc.delete(@path, annotation_id)
            annotations = svc.list_for_book(@path)
            @reader_session_mutator.update_reader(annotations: annotations)

            new_index = [current_index, annotations.length - 1].min
            new_index = 0 if new_index.negative?
            @reader_session_mutator.update_sidebar(
              annotations_selected: new_index,
              sidebar_annotations_selected: new_index
            )
            new_index
          end


          private

          def assign_session_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @ui_state = deps.ui_state
            @sidebar_state = deps.sidebar_state
            @reader_session_mutator = deps.reader_session_mutator
            @rendered_content_reader = deps.rendered_content_reader
          end

          def assign_document_dependencies(deps)
            @doc = deps.doc
            @document_reader = deps.document_reader
            @path = deps.path
            @terminal_service = deps.terminal_service
            @page_calculator = deps.page_calculator
            @layout_service = deps.layout_service
            @process_control = deps.process_control
          end

          def assign_service_dependencies(deps)
            @progress_repository = deps.progress_repository
            @bookmark_repository = deps.bookmark_repository
            @annotation_service = deps.annotation_service
            @logger = deps.logger
            @navigation_service = deps.navigation_service
            @bookmark_service = deps.bookmark_service
            @notification_service = deps.notification_service
            @coordinate_service = deps.coordinate_service
          end


          def canonical_path_for_doc
            current_doc&.canonical_path || @path
          end

          def collect_progress_data
            if @config_reader.page_numbering_mode == :dynamic && @page_calculator
              collect_dynamic_progress(@page_calculator)
            else
              collect_absolute_progress
            end
          end

          def collect_dynamic_progress(page_calculator)
            width = (@ui_state.terminal_width || 80).to_i
            height = (@ui_state.terminal_height || 24).to_i
            page_data = page_calculator.get_page(
              @reader_state.current_page_index,
              width: width,
              height: height,
              sidebar_visible: @reader_state.sidebar_visible? == true
            )
            return { chapter: 0, line_offset: 0 } unless page_data

            {
              chapter: page_data[:chapter_index],
              line_offset: page_data[:start_line],
            }
          end

          def collect_absolute_progress
            line_offset = if @config_reader.view_mode == :split
                            @reader_state.left_page
                          else
                            @reader_state.single_page
                          end

            {
              chapter: @reader_state.current_chapter,
              line_offset: line_offset,
            }
          end

          def apply_progress_data(progress)
            unless progress.is_a?(Shoko::Core::Models::ReadingProgress)
              raise ArgumentError, 'progress_repository must return Core::Models::ReadingProgress'
            end

            chapter = progress.chapter_index.to_i
            line_offset = progress.line_offset.to_i

            apply_chapter(chapter)
            apply_page_position(line_offset)
          end

          def apply_chapter(chapter)
            doc = current_doc
            return unless doc

            valid_chapter = chapter >= doc.chapter_count ? 0 : chapter
            @reader_session_mutator.update_reader(current_chapter: valid_chapter)
          end

          def current_doc
            @document_reader&.call || @doc
          end

          def apply_page_position(line_offset)
            if dynamic_page_mode?
              apply_dynamic_page_position(line_offset)
            else
              apply_absolute_page_position(line_offset)
            end
          end

          def dynamic_page_mode?
            @config_reader.page_numbering_mode == :dynamic && @page_calculator
          end

          def apply_dynamic_page_position(line_offset)
            estimate_and_set_page_index(line_offset)
            store_pending_progress(line_offset)
          end

          def estimate_and_set_page_index(line_offset)
            width = (@ui_state.terminal_width || 80).to_i
            height = (@ui_state.terminal_height || 24).to_i
            layout = @layout_service
            _, content_height = layout.calculate_metrics(width, height, @config_reader.view_mode)
            lines_per_page = layout.adjust_for_line_spacing(content_height, @config_reader.line_spacing)
            est_index = lines_per_page.positive? ? (line_offset.to_f / lines_per_page).floor : 0
            @reader_session_mutator.update_reader(current_page_index: est_index)
          end

          def store_pending_progress(line_offset)
            @reader_session_mutator.update_reader(
              pending_progress: {
                chapter_index: @reader_state.current_chapter,
                line_offset: line_offset,
              }
            )
          end

          def apply_absolute_page_position(line_offset)
            @reader_session_mutator.update_reader(single_page: line_offset, left_page: line_offset)
          end


          def persist_bookmark
            return @bookmark_service.add_bookmark if @bookmark_service

            sync_bookmarks_from_repository
          end

          def sync_bookmarks_from_repository
            position = current_bookmark_position
            canonical = canonical_path_for_doc
            bookmarks = fetch_bookmarks_after_add(canonical, position)
            @reader_session_mutator.update_reader(bookmarks: bookmarks)
          end

          def fetch_bookmarks_after_add(canonical, position)
            @bookmark_repository.add_for_book(
              canonical,
              chapter_index: position[:chapter],
              line_offset: position[:line_offset],
              text_snippet: ''
            )
            @bookmark_repository.find_by_book_path(canonical)
          rescue Shoko::Error
            @reader_state.bookmarks || []
          end

          def selected_bookmark
            bookmarks = bookmarks_list
            selected_idx = @sidebar_state.sidebar_bookmarks_selected || 0
            bookmarks[selected_idx]
          end

          def jump_to_bookmark_chapter(chapter_index)
            if @navigation_service
              @navigation_service.jump_to_chapter(chapter_index)
            else
              @reader_session_mutator.update_reader(current_chapter: chapter_index)
            end
          end

          def apply_bookmark_position(chapter_index, offset)
            payload = bookmark_position_payload(offset)
            page_index = bookmark_page_index(chapter_index, offset)
            payload[:current_page_index] = page_index if page_index
            @reader_session_mutator.update_reader(**payload)
            save_progress
            @reader_session_mutator.update_reader(mode: :read)
          end

          def bookmark_position_payload(offset)
            stride = split_stride_for_state
            { single_page: offset, left_page: offset, right_page: offset + stride, current_page: offset }
          end

          def bookmark_page_index(chapter_index, offset)
            return nil unless dynamic_page_numbering? && @page_calculator

            @page_calculator.find_page_index(chapter_index, offset)
          end

          def split_stride_for_state
            return 1 unless @layout_service

            width, height = layout_dimensions
            _, content_height = @layout_service.calculate_metrics(width, height, :split)
            spacing = current_line_spacing
            stride = @layout_service.adjust_for_line_spacing(content_height, spacing)
            normalized_stride(stride)
          end

          def current_bookmark_position
            chapter = @reader_state.current_chapter || 0
            dynamic_bookmark_position(chapter) || absolute_bookmark_position(chapter)
          rescue Shoko::Error
            { chapter: chapter, line_offset: 0 }
          end

          def dynamic_bookmark_position(chapter)
            return nil unless dynamic_page_numbering? && @page_calculator

            width, height = layout_dimensions
            page = @page_calculator.get_page(
              @reader_state.current_page_index || 0,
              width: width,
              height: height,
              sidebar_visible: @reader_state.sidebar_visible? == true
            )
            return nil unless page

            {
              chapter: page[:chapter_index] || chapter,
              line_offset: page[:start_line].to_i,
            }
          end

          def absolute_bookmark_position(chapter)
            view_mode = @config_reader.view_mode
            line_offset = view_mode == :split ? @reader_state.left_page : @reader_state.single_page
            { chapter: chapter, line_offset: line_offset || 0 }
          end

          def layout_dimensions
            width = @ui_state.terminal_width
            height = @ui_state.terminal_height
            return normalized_dimensions(width, height) unless (!width || !height) && @terminal_service

            term_height, term_width = @terminal_service.size
            normalized_dimensions(term_width, term_height)
          end

          def normalized_dimensions(width, height)
            width_value = width.to_i
            height_value = height.to_i
            width_value = 80 if width_value <= 0
            height_value = 24 if height_value <= 0
            [width_value, height_value]
          end

          def current_line_spacing
            @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
          end

          def normalized_stride(stride)
            stride_value = stride.to_i
            stride_value.positive? ? stride_value : 1
          end

          def current_chapter_label
            (@reader_state.current_chapter || 0) + 1
          end

          def current_page_label
            if dynamic_page_numbering?
              ((@reader_state.current_page_index || 0).to_i + 1)
            else
              @reader_state.current_page || 0
            end
          end

          def dynamic_page_numbering?
            @config_reader.page_numbering_mode == :dynamic
          end

          def bookmarks_list
            @reader_state.bookmarks
          end


          def normalize_selection_for_state(range)
            return nil unless range

            return range if anchor_range?(range)

            coord = resolve_coordinate_service
            return nil unless coord

            rendered = @rendered_content_reader.rendered_lines
            coord.normalize_selection_range(range, rendered)
          end

          def anchor_range?(range)
            return false unless range.is_a?(Hash)

            normalized = range.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end
            start_anchor = normalized[:start]
            start_anchor.is_a?(Hash) && start_anchor.key?(:geometry_key)
          end

          def resolve_coordinate_service
            @coordinate_service
          end

          def normalize_annotation(annotation)
            return {} unless annotation.is_a?(Hash)

            annotation.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end
          end

        end
      end
    end
  end
end
