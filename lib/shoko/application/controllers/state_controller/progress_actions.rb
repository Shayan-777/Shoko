# frozen_string_literal: true

module Shoko
  module Application
    module Controllers
      module StateControllerProgressActions
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
          progress = @progress_repository.find_by_book_path(@path) if !progress && @path != canonical
          return unless progress

          apply_progress_data(progress)
        end

        def quit_to_menu
          save_progress
          @state_writer.quit_to_menu
        end

        def quit_application
          save_progress
          @terminal_service.cleanup
          @process_control&.terminate(0)
        end

        private

        def canonical_path_for_doc
          @doc.respond_to?(:canonical_path) ? @doc.canonical_path : @path
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
            sidebar_visible: @reader_state.sidebar_visible == true
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
          @state_writer.update_reader(current_chapter: valid_chapter)
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
          _, content_height = layout.calculate_metrics(
            width, height, @config_reader.view_mode
          )
          lines_per_page = layout.adjust_for_line_spacing(
            content_height, @config_reader.line_spacing
          )
          est_index = lines_per_page.positive? ? (line_offset.to_f / lines_per_page).floor : 0
          @state_writer.update_page(current_page_index: est_index)
        rescue StandardError
          # best-effort; leave index as-is if estimation fails
        end

        def store_pending_progress(line_offset)
          @state_writer.update_selections(
            pending_progress: {
              chapter_index: @reader_state.current_chapter,
              line_offset: line_offset,
            }
          )
        end

        def apply_absolute_page_position(line_offset)
          @state_writer.update_page(
            single_page: line_offset, left_page: line_offset
          )
        end
      end
    end
  end
end
