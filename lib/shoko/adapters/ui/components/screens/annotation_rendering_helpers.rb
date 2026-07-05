# frozen_string_literal: true

require_relative '../ui/text_utils'
require_relative '../ui/annotation_markup'
require 'shoko/shared/hash_normalizer'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/terminal/text_sanitizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Shared state access for annotation detail and edit screens.
          module AnnotationScreenRendering
            private

            def resolve_book_label
              book_path = resolve_menu_reader&.selected_annotation_book
              return 'Unknown Book' unless book_path

              raw = File.basename(book_path)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(raw, preserve_newlines: false, preserve_tabs: false)
            end

            def resolve_menu_reader
              return @menu_state_reader if defined?(@menu_state_reader) && @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader if defined?(@dependencies)
              @menu_state_reader
            end
          end

          # Normalized view of annotation data for screen rendering.
          class AnnotationView
            def initialize(annotation)
              @annotation = if annotation.is_a?(Hash)
                              Shoko::Shared::HashNormalizer.deep_symbolize(annotation) || {}
                            else
                              {}
                            end
            end

            def text
              fetch(:text).to_s
            end

            def note
              fetch(:note).to_s
            end

            def chapter_index
              fetch(:chapter_index)
            end

            def id
              fetch(:id)
            end

            def formatted_date
              created = fetch(:created_at)
              created.to_s.tr('T', ' ').sub('Z', '')
            end

            private

            def fetch(key)
              @annotation[key]
            end
          end

          # Text box helper for annotation screens.
          class AnnotationTextBox
            BOX_COLUMN = 2
            TEXT_COLUMN = 4
            BOX_SPACING = 2
            MIN_HEIGHT = 6
            BOTTOM_PADDING = 3

            attr_reader :row, :height, :width, :label, :text, :style

            def initialize(row:, height:, width:, label:, text:, style: :plain)
              @row = row
              @height = height
              @width = width
              @label = label
              @text = text.to_s
              @style = style
            end

            def inner_width
              width - 4
            end

            def frame_args
              {
                row: row,
                height: height,
                width: width,
                label: label,
              }
            end

            def each_visible_line(&block)
              return enum_for(__method__) unless block

              lines = if style == :markup
                        Ui::AnnotationMarkup::Styler.new(text).render_lines(inner_width)
                      else
                        Ui::TextUtils.wrap_text(text, inner_width)
                      end

              lines.first(max_lines).each_with_index(&block)
            end

            def render(context, drawer:, color_prefix:)
              drawer.draw_box(
                context.surface,
                context.bounds,
                Ui::BoxDrawer::BoxSpec.new(
                  row: row,
                  col: BOX_COLUMN,
                  height: height,
                  width: width
                ),
                label: label
              )
              render_lines(context, color_prefix: color_prefix)
            end

            def render_lines(context, color_prefix:)
              line_reset = Ui::AnnotationMarkup::STYLE_RESET

              each_visible_line do |line, index|
                display = style == :markup ? (line + line_reset) : line
                padded = Ui::TextUtils.pad_right(display, inner_width)
                context.surface.write(
                  context.bounds,
                  row + 1 + index,
                  TEXT_COLUMN,
                  "#{color_prefix}#{padded}#{context.reset}"
                )
              end
            end

            def cursor_position(cursor)
              return markup_cursor_position(cursor) if style == :markup

              plain_cursor_position(cursor)
            end

            def next_box(total_height:, label:, text:, style: nil)
              next_row = row + height + BOX_SPACING
              next_height = [total_height - next_row - BOTTOM_PADDING, MIN_HEIGHT].max
              AnnotationTextBox.new(
                row: next_row,
                height: next_height,
                width: width,
                label: label,
                text: text,
                style: style || @style
              )
            end

            private

            def max_lines
              [height - 2, 0].max
            end

            def markup_cursor_position(cursor)
              renderer = Ui::AnnotationMarkup::Styler.new(text)
              line_idx, col = renderer.cursor_position(cursor, inner_width)
              [row + 1 + line_idx, TEXT_COLUMN + col]
            end

            def plain_cursor_position(cursor)
              cursor_lines = Ui::TextUtils.wrap_text(text[0, cursor], inner_width)
              last_line = cursor_lines.last || ''
              cursor_row = row + 1 + [cursor_lines.length - 1, 0].max
              cursor_col = TEXT_COLUMN + Shoko::Shared::Terminal::TextMetrics.visible_length(last_line)
              [cursor_row, cursor_col]
            end
          end

          # Menu-state helper for annotation edit screens.
          class AnnotationEditState
            def initialize(dependencies = nil)
              @dependencies = dependencies
              @menu_state_reader = nil
              @menu_session_mutator = nil
            end

            def text
              (menu_state_reader&.annotation_edit_text || '').to_s
            end

            def cursor(text = self.text)
              (menu_state_reader&.annotation_edit_cursor || text.length).to_i
            end

            def update_from
              current_text = text
              current_cursor = cursor(current_text)
              updated = yield(current_text, current_cursor)
              update(text: updated[0], cursor: updated[1]) if updated
            end

            def update(text:, cursor:)
              menu_session_mutator&.update_menu(annotation_edit_text: text, annotation_edit_cursor: cursor)
            end

            def selected_annotation
              ann = menu_state_reader&.selected_annotation
              return unless ann.is_a?(Hash)

              ann.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
            end

            def annotation_update_payload
              annotation = selected_annotation || {}
              path = menu_state_reader&.selected_annotation_book
              ann_id = annotation[:id]
              return nil unless path && ann_id

              { path: path, ann_id: ann_id, text: text }
            end

            def refresh_annotations(service)
              menu_session_mutator&.update_menu(annotations_all: service.list_all)
            end

            def return_to_annotations_list
              menu_session_mutator&.update_menu(mode: :annotations)
            end

            private

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def menu_session_mutator
              @menu_session_mutator ||= @dependencies&.menu_session_mutator
            end
          end
        end
      end
    end
  end
end
