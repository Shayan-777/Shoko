# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module StateControllerAnnotationActions
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

            normalized = range.each_with_object({}) do |(key, value), result|
              result[key.is_a?(String) ? key.to_sym : key] = value
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
