# frozen_string_literal: true

require_relative '../base_component'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/text_utils'
require 'shoko/shared/terminal/text_sanitizer'
require_relative 'annotation_rendering_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Detail view for one annotation: the selected passage as a muted,
          # quote-marked block and the note beneath it in the primary tone —
          # the in-book notes panel's reading order, given the whole canvas.
          # Small dim labels separate the sections; no divider lines.
          class AnnotationDetailScreenComponent < BaseComponent
            include Ui::TextUtils
            include AnnotationScreenRendering

            Palette = StatusBar::Palette

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
            end

            def do_render(surface, bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              annotation = selected_annotation
              view = annotation ? AnnotationView.new(annotation) : nil
              frame.render_rule(title: 'Annotation', accent: accent, meta: rule_meta(view))
              return render_empty(frame) unless view

              render_sections(frame, view)
              frame.render_hint('O open in book · E edit · D delete · ESC back')
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def accent
              MenuDesign::ViewAccents.for(:annotations)
            end

            def rule_meta(view)
              return '' unless view

              parts = [compact_book_label]
              parts << "Ch #{view.chapter_index}" if view.chapter_index
              saved = view.formatted_date.to_s.strip
              parts << "saved #{saved.split.first}" unless saved.empty?
              parts.join(' · ')
            end

            def render_empty(frame)
              row = frame.body_top + [frame.body_height / 2, 0].max - 1
              frame.write_line(row, [['Select an annotation from the list to inspect it.',
                                      Palette::LANDING_DIM_FG]])
              frame.render_hint('ESC back')
            end

            def render_sections(frame, view)
              budgets = section_budgets(frame)
              row = render_quote_section(frame, view, frame.body_top, budgets[:quote])
              render_note_section(frame, view, row + 1, budgets[:note])
            end

            def render_quote_section(frame, view, top, budget)
              frame.write_line(top, [['SELECTED TEXT', Palette::LANDING_DIM_FG]])
              lines = wrap_block(view.text, frame.content_width - 4, empty: 'No selected text.')
              write_quoted_lines(frame, lines.first(budget), top + 1)
            end

            def write_quoted_lines(frame, lines, row)
              lines.each_with_index do |line, offset|
                lead = offset.zero? ? '❝ ' : '  '
                frame.write_line(row + offset, [[lead, Palette::LANDING_DIM_FG],
                                                [line, Palette::NOTES_EXCERPT_FG]])
              end
              row + lines.length
            end

            def render_note_section(frame, view, top, budget)
              return if top > frame.body_bottom

              frame.write_line(top, [['NOTE', Palette::LANDING_DIM_FG]])
              lines = wrap_block(view.note, frame.content_width - 4, empty: 'No note added yet.')
              lines.first(budget).each_with_index do |line, offset|
                break if top + 1 + offset > frame.body_bottom

                frame.write_line(top + 1 + offset, [['  ', nil], [line, Palette::NOTES_NOTE_FG]])
              end
            end

            def section_budgets(frame)
              available = [frame.body_height - 3, 4].max
              quote = (available * 0.5).floor.clamp(2, available - 2)
              { quote: quote, note: [available - quote, 2].max }
            end

            def wrap_block(text, width, empty:)
              clean = safe_text(text.to_s)
              clean = empty if clean.strip.empty?
              wrap_words(clean, [width, 8].max)
            end

            def compact_book_label
              safe_text(resolve_book_label.to_s)
            end

            def selected_annotation
              ann = menu_state_reader&.selected_annotation
              ann if ann.is_a?(Hash)
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
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
