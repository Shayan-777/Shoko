# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../ui/text_utils'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/status_renderer'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../../../../shared/terminal/ansi'
require_relative 'annotation_rendering_helpers'
require_relative 'annotation_detail_screen_component/section_support'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Detailed view for a selected annotation with readable sections.
          class AnnotationDetailScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils
            include AnnotationScreenRendering
            include AnnotationDetailScreenSectionSupport

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
            end

            def do_render(surface, bounds)
              annotation = selected_annotation
              view = annotation ? AnnotationView.new(annotation) : nil

              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Annotation Detail', hint: 'O open  E edit  D delete  ESC back')
              frame.render_divider

              unless view
                render_empty(surface, bounds)
                frame.render_footer(text: 'No annotation selected')
                return
              end

              layout = compute_layout(bounds)
              render_status(surface, bounds, layout, view)
              render_sections(surface, bounds, layout, view)
              frame.render_footer(text: footer_text(view))
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def render_empty(surface, bounds)
              MenuDesign::StatusRenderer.new(surface, bounds).render_empty(
                row: bounds.height / 2,
                indent: 2,
                message: 'Select an annotation from the list to inspect details.',
                color: COLOR_TEXT_DIM
              )
            end

            def render_status(surface, bounds, layout, annotation)
              left = "Book • #{resolve_book_label}"
              right_parts = [
                "Ch #{annotation.chapter_index || '—'}",
                annotation.page_meta && "Page #{annotation.page_meta}",
              ].compact

              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:content_indent],
                left: truncate_text(left, [layout[:content_width] - 10, 8].max),
                right: right_parts.join('  •  '),
                width: layout[:content_width],
                left_color: COLOR_TEXT_DIM,
                right_color: COLOR_TEXT_DIM
              )
            end

            def wrap_block(text, width, empty:)
              clean = safe_text(text.to_s)
              clean = empty if clean.strip.empty?
              wrap_text(clean, [width, 8].max)
            end

            def compute_layout(bounds)
              content_width = MenuDesign::Layout.centered_content_width(
                bounds,
                preferred: 104,
                min: 52,
                horizontal_padding: 8
              )
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)

              {
                status_row: 3,
                content_indent: indent,
                content_width: content_width,
                content_top: 5,
                content_bottom: bounds.height - 2,
              }
            end

            def footer_text(annotation)
              saved = annotation.formatted_date.to_s.strip
              saved = 'unknown' if saved.empty?
              "Saved #{saved}"
            end

            def selected_annotation
              ann = menu_state_reader&.selected_annotation
              ann if ann.is_a?(Hash)
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
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
