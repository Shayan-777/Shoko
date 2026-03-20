# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'
require_relative 'annotations_screen_component/layout_support'
require_relative 'annotations_screen_component/list_renderer'
require_relative 'annotations_screen_component/preview_renderer'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../../../../shared/terminal/ansi'
require_relative '../../../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Annotation browser with list + contextual preview workspace.
          class AnnotationsScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include AnnotationsScreenComponentLayoutSupport
            include AnnotationsScreenComponentListRenderer
            include AnnotationsScreenComponentPreviewRenderer
            include Ui::TextUtils

            SPLIT_MIN_WIDTH = 100
            PREVIEW_WIDTH_MIN = 34
            PREVIEW_WIDTH_MAX = 42
            PREVIEW_GAP = 3

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @reader_state_reader = nil
              @menu_state_reader = nil
              @selected = 0
              @list = []
              @mode = :book
              @current_book_path = nil
              @current_annotation = nil
              refresh_data
            end

            attr_reader :selected, :current_annotation, :current_book_path

            def selected=(value)
              @selected = [value, 0].max
              update_current_annotation
            end

            def navigate(direction)
              annotations = current_annotations
              return if annotations.empty?

              case direction
              when :up then @selected = [@selected - 1, 0].max
              when :down then @selected = [@selected + 1, annotations.length - 1].min
              end

              update_current_annotation
            end

            def refresh_data
              prev_selected = @selected
              load_annotations_for_mode
              clamp_selection(prev_selected)
              update_current_annotation
            end

            def do_render(surface, bounds)
              refresh_data
              annotations = current_annotations
              layout = compute_layout(bounds, split_allowed: annotations.any?)
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              render_frame(frame)
              return render_empty_annotations(surface, bounds, frame) if annotations.empty?

              render_annotations_workspace(surface, bounds, layout, annotations.length)
              frame.render_footer(text: footer_text(annotations.length))
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def render_frame(frame)
              frame.render_title(title: 'Annotations', hint: 'ENTER open  E edit  D delete  ESC back')
              frame.render_divider
            end

            def render_empty_annotations(surface, bounds, frame)
              render_empty_state(surface, bounds)
              frame.render_footer(text: 'No annotations yet')
            end

            def render_annotations_workspace(surface, bounds, layout, total)
              render_status_row(surface, bounds, layout, total)
              render_list(surface, bounds, layout, current_annotations)
              render_preview_area(
                surface: surface,
                bounds: bounds,
                layout: layout,
                annotation: current_annotation,
                total: total
              )
            end

            def render_preview_area(surface:, bounds:, layout:, annotation:, total:)
              if layout[:preview_panel]
                render_preview(surface, bounds, preview_context(layout, annotation, total))
              else
                render_compact_preview(surface, bounds, layout, annotation)
              end
            end

            def current_annotations
              @list || []
            end

            def load_annotations_for_mode
              path = reader_state_reader&.book_path
              if path && !path.to_s.empty?
                load_book_annotations(path)
              else
                load_all_annotations
              end
            end

            def load_book_annotations(path)
              @mode = :book
              @current_book_path = path
              raw = reader_state_reader&.annotations || []
              @list = normalize_list(raw).map { |a| a.merge(book_path: path) }
            end

            def load_all_annotations
              @mode = :all
              mapping = menu_state_reader&.annotations_all || {}
              @list = mapping.flat_map do |book_path, items|
                normalize_list(items).map { |a| a.merge(book_path: book_path) }
              end
            end

            def reader_state_reader
              return @reader_state_reader if @reader_state_reader

              @reader_state_reader = @dependencies&.reader_state_reader
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
            end

            def clamp_selection(prev_selected)
              upper = [current_annotations.length - 1, 0].max
              @selected = prev_selected.clamp(0, upper)
            end

            def update_current_annotation
              annotations = current_annotations
              @current_annotation = annotations[@selected] if @selected < annotations.length
              return unless @current_annotation

              book_path = @current_annotation[:book_path]
              @current_book_path = book_path if book_path
            end

            def render_empty_state(surface, bounds)
              MenuDesign::StatusRenderer.new(surface, bounds).render_empty(
                row: bounds.height / 2,
                indent: 2,
                message: 'No annotations found. Create one while reading to populate this workspace.',
                color: COLOR_TEXT_DIM
              )
            end

            def normalize_list(raw)
              (raw || []).map do |a|
                annotation = normalize_annotation(a)
                {
                  text: annotation[:text],
                  note: annotation[:note],
                  id: annotation[:id],
                  range: annotation[:range],
                  chapter_index: annotation[:chapter_index],
                  created_at: annotation[:created_at],
                  updated_at: annotation[:updated_at],
                  page_current: annotation[:page_current],
                  page_total: annotation[:page_total],
                  page_mode: annotation[:page_mode],
                }
              end
            end

            def normalize_annotation(annotation)
              Shoko::Shared::HashNormalizer.deep_symbolize(annotation) || {}
            end

            def created_at_label(value)
              text = value.to_s
              saved = text.split('T', 2).first.to_s
              saved.empty? ? '—' : saved
            end
          end
        end
      end
    end
  end
end
