# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Layout and text-formatting helpers for annotations workspace rendering.
          module AnnotationsScreenComponentLayoutSupport
            private

            def compute_layout(bounds, split_allowed:)
              content_width = MenuDesign::Layout.centered_content_width(bounds, preferred: 108, min: 58,
                                                                                horizontal_padding: 8)
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)
              list_width, preview_panel = preview_layout(bounds, content_width, indent, split_allowed)

              {
                status_row: 3,
                header_row: 4,
                list_start_row: 6,
                list_bottom_row: bounds.height - 2,
                list_height: [bounds.height - 7, 1].max,
                list_indent: indent,
                list_render_width: list_width,
                list_columns: compute_columns(list_width),
                preview_panel: preview_panel,
              }
            end

            def preview_layout(bounds, content_width, indent, split_allowed)
              return [content_width, nil] unless split_preview?(bounds, content_width, split_allowed)

              preview_width = (content_width * 0.35).to_i.clamp(
                AnnotationsScreenComponent::PREVIEW_WIDTH_MIN,
                AnnotationsScreenComponent::PREVIEW_WIDTH_MAX
              )
              list_width = content_width - preview_width - AnnotationsScreenComponent::PREVIEW_GAP
              return [content_width, nil] if list_width < 40

              [list_width, build_preview_panel(bounds, indent, list_width, preview_width)]
            end

            def split_preview?(bounds, content_width, split_allowed)
              split_allowed &&
                content_width >= AnnotationsScreenComponent::SPLIT_MIN_WIDTH &&
                bounds.height >= 20
            end

            def build_preview_panel(bounds, indent, list_width, preview_width)
              {
                x: indent + list_width + AnnotationsScreenComponent::PREVIEW_GAP,
                y: 4,
                width: preview_width,
                height: [bounds.height - 6, 6].max,
              }
            end

            def compute_columns(list_width)
              idx = 4
              chapter = 4
              note = 6
              saved = 10
              gap = 2
              excerpt = [list_width - idx - chapter - note - saved - (gap * 4), 12].max
              { idx: idx, chapter: chapter, excerpt: excerpt, note: note, saved: saved }
            end

            def footer_text(count)
              "#{count} annotations"
            end

            def format_chapter(chapter_index)
              chapter_index.nil? ? '—' : chapter_index.to_i.to_s
            end

            def one_line(text, fallback:)
              raw = safe_text(text.to_s.tr("\n", ' ').strip)
              raw.empty? ? fallback : raw
            end

            def build_book_label(all_mode:)
              return sanitize_filename(File.basename(@current_book_path)) if @current_book_path

              all_mode ? 'All Books' : 'No book selected'
            end

            def build_book_cell(annotation, width)
              book = annotation[:book_path] ? sanitize_filename(File.basename(annotation[:book_path])) : ''
              pad_right(truncate_text(book, width), width)
            end

            def sanitize_filename(raw)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(raw, preserve_newlines: false, preserve_tabs: false)
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text, preserve_newlines: false, preserve_tabs: false)
            end
          end
        end
      end
    end
  end
end
