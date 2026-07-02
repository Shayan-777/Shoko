# frozen_string_literal: true

require_relative 'dependencies/state_controller_dependencies'
require_relative 'support/message_notifier'
require 'shoko/core/models/reading_progress'
require 'shoko/core/models/reader_settings'
require 'shoko/core/models/document_anchor'

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

          # Progress autosave fires on every page turn / chapter change and on
          # quit. A transient write failure (disk full, read-only mount, revoked
          # permission, quota) must not unwind the event loop — losing the latest
          # position is the documented cost of autosave; losing the whole reading
          # session is not. PersistenceError is a Shoko::Error, so this contains it.
          def save_progress
            return unless @path && current_doc

            progress_data = collect_progress_data
            canonical = canonical_path_for_doc

            @progress_repository.save_for_book(canonical,
                                               chapter_index: progress_data[:chapter],
                                               line_offset: progress_data[:line_offset],
                                               anchor: capture_line_anchor(progress_data)&.to_h)
          rescue Shoko::Error => e
            @logger&.error('Failed to save progress', error: e.class.name, message: e.message, path: @path)
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

          # Land on a saved annotation by re-locating its layout-independent
          # anchor in the current pagination: the quote (or position ratio) is
          # resolved to a wrapped-line offset and jumped to precisely, so the
          # reader arrives at the annotated line regardless of the size it was
          # created at. Falls back to the chapter start only when the anchor
          # cannot be located (e.g. the quote no longer exists).
          def jump_to_annotation(annotation)
            normalized = normalize_annotation(annotation)
            return if normalized.empty?

            chapter_index = normalized[:chapter_index].to_i
            line_offset = annotation_line_offset(normalized, chapter_index)

            if line_offset
              jump_to_chapter_offset(chapter_index, line_offset)
            elsif @navigation_service
              @navigation_service.jump_to_chapter(chapter_index)
            else
              @reader_session_mutator.update_reader(current_chapter: chapter_index)
            end

            @reader_session_mutator.update_reader(mode: :read)
          end

          # Land on a saved bookmark by re-locating its layout-independent
          # anchor in the current pagination (annotation-jump parity); the
          # stored wrapped-line offset is the fallback for legacy records and
          # unresolvable anchors.
          def jump_to_bookmark(bookmark)
            return unless bookmark

            chapter_index = bookmark.chapter_index.to_i
            resolved = resolve_position_anchor(bookmark.anchor, chapter_index)
            if @bookmark_service
              @bookmark_service.jump_to_bookmark(bookmark, line_offset: resolved)
            else
              jump_to_chapter_offset(chapter_index, resolved || bookmark.line_offset.to_i)
            end
          end

          def jump_to_chapter_offset(chapter_index, line_offset)
            return unless chapter_index

            if @navigation_service
              @navigation_service.jump_to_chapter_offset(chapter_index, line_offset)
            else
              offset = [line_offset.to_i, 0].max
              @reader_session_mutator.update_reader(
                current_chapter: chapter_index, current_page: offset,
                single_page: offset, left_page: offset,
                right_page: offset + split_stride_for_state
              )
            end
            save_progress
          end

          def delete_annotation_by_id(annotation)
            current_index = @reader_state.annotations_overlay_selected || 0
            normalized = normalize_annotation(annotation)
            annotation_id = normalized[:id]

            svc = @annotation_service
            return current_index unless svc && annotation_id

            svc.delete(@path, annotation_id)
            annotations = svc.list_for_book(@path)
            @reader_session_mutator.update_reader(annotations: annotations)

            new_index = [current_index, annotations.length - 1].min
            new_index = 0 if new_index.negative?
            @reader_session_mutator.update_reader(annotations_overlay_selected: new_index)
            new_index
          end

          # The current reading position as { chapter:, line_offset: } — the
          # numbering-mode-aware anchor used to tie a new note to where the reader is.
          def current_reading_position
            collect_progress_data
          end

          # The page number (1-based) for a stored position under the CURRENT layout.
          # Recomputed from the live page map, so it stays correct after the terminal
          # is resized / repaginated (returns nil when the map isn't ready).
          def page_number_for(chapter_index, line_offset)
            return nil unless @page_calculator && line_offset

            index = @page_calculator.find_page_index(chapter_index.to_i, line_offset.to_i)
            index.nil? ? nil : index + 1
          end

          # Capture a layout-independent quote anchor for newly-annotated text, while
          # the selection geometry is live. Owned here because the state controller
          # holds the anchor resolver (the same one that resolves jumps/highlights).
          def capture_quote_anchor(quote:, chapter_index:, line_offset_hint: nil)
            return nil unless @anchor_resolver

            @anchor_resolver.capture_quote(
              quote: quote.to_s, chapter_index: chapter_index.to_i, line_offset_hint: line_offset_hint
            ).to_h
          end

          # Capture a position-ratio anchor for a page/chapter note from the current
          # reading position.
          def capture_position_anchor(chapter_index:)
            return nil unless @anchor_resolver

            position = current_reading_position
            line_offset = position && position[:line_offset]
            return nil if line_offset.nil?

            @anchor_resolver.capture_position(chapter_index: chapter_index.to_i, line_offset: line_offset.to_i).to_h
          end

          # The page number a saved annotation currently sits on, by resolving its
          # anchor against the live layout (nil when it has no anchor or the map
          # isn't ready). Used to render each note's page in the notes list.
          def page_for_annotation(annotation)
            normalized = normalize_annotation(annotation)
            chapter_index = normalized[:chapter_index].to_i
            line_offset = annotation_line_offset(normalized, chapter_index)
            line_offset && page_number_for(chapter_index, line_offset)
          end

          private

          def assign_session_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @ui_state = deps.ui_state
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
            @anchor_resolver = deps.anchor_resolver
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
              height: height
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
            line_offset = resolve_position_anchor(progress.anchor, chapter) || progress.line_offset.to_i

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
            return sync_bookmarks_from_repository unless @bookmark_service

            @bookmark_service.add_bookmark(nil, anchor: capture_line_anchor(current_reading_position)&.to_h)
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
              text_snippet: '',
              anchor: capture_line_anchor(position)&.to_h
            )
            @bookmark_repository.find_by_book_path(canonical)
          rescue Shoko::Error
            @reader_state.bookmarks || []
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
              height: height
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

          # Layout-independent anchor for a { chapter:, line_offset: } reading
          # position — the top visible line captured as a quote anchor.
          # Capture is best-effort: persisting the raw offsets must never fail
          # because the anchor could not be built (formatter edge cases, image
          # chapters), so any error degrades to "no anchor".
          def capture_line_anchor(position)
            return nil unless @anchor_resolver && position

            anchor = @anchor_resolver.capture_line(
              chapter_index: position[:chapter].to_i,
              line_offset: position[:line_offset].to_i
            )
            return nil if anchor.nil? || anchor.empty?

            anchor
          # resilient-boundary
          rescue StandardError => e
            swallow_anchor_capture_error(e)
          end

          def swallow_anchor_capture_error(error)
            @logger&.debug('progress.anchor_capture_failed',
                           error_class: error.class.name, error: error.message)
            nil
          end

          # Best-effort anchor→offset resolution against the CURRENT layout.
          # Runs during startup restore, where a resolution failure must
          # degrade to the stored raw offset, never abort opening the book.
          def resolve_position_anchor(anchor, chapter_index)
            return nil unless @anchor_resolver && anchor

            @anchor_resolver.line_offset_for(anchor, chapter_index: chapter_index)
          # resilient-boundary
          rescue StandardError => e
            swallow_anchor_resolve_error(e)
          end

          def swallow_anchor_resolve_error(error)
            @logger&.debug('progress.anchor_resolve_failed',
                           error_class: error.class.name, error: error.message)
            nil
          end

          # Resolve a saved annotation's DocumentAnchor to a wrapped-line offset
          # in the current layout, or nil when it has no anchor / cannot be
          # located.
          def annotation_line_offset(normalized, chapter_index)
            return nil unless @anchor_resolver

            anchor = annotation_anchor(normalized)
            return nil unless anchor

            @anchor_resolver.line_offset_for(anchor, chapter_index: chapter_index)
          end

          def annotation_anchor(normalized)
            anchor = Shoko::Core::Models::DocumentAnchor.from_h(normalized[:anchor])
            anchor unless anchor.nil? || anchor.empty?
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
