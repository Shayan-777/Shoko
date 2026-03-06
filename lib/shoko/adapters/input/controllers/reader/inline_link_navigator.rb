# frozen_string_literal: true

require 'cgi'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Resolves and applies in-book inline link clicks (for example footnote refs).
          class InlineLinkNavigator
            def initialize(coordinate_service:, rendered_content_reader:, reader_state_reader:, document_reader:,
                           state_controller:, anchor_resolver:, logger: nil)
              @coordinate_service = coordinate_service
              @rendered_content_reader = rendered_content_reader
              @reader_state_reader = reader_state_reader
              @document_reader = document_reader
              @state_controller = state_controller
              @anchor_resolver = anchor_resolver
              @logger = logger
              @chapter_index_map_key = nil
              @chapter_index_map = {}
            end

            def navigate(event)
              context = navigation_context_for(event)
              return false unless context

              href = context.fetch(:href)
              entry = context.fetch(:entry)
              destination = destination_for(href, entry)
              return false unless destination

              @state_controller.jump_to_chapter_offset(destination[:chapter_index], destination[:line_offset])
              true
            rescue Shoko::Error, ArgumentError => e
              @logger&.debug(
                'inline_link_navigator.navigate_failed',
                error: e.class.name,
                message: e.message
              )
              false
            end

            def link_hit_for_event(event)
              context = link_context_for(event)
              return nil unless context

              span = context.fetch(:span)
              geometry = context.fetch(:geometry)
              entry = context.fetch(:entry)
              {
                href: context.fetch(:href),
                line_offset: geometry.line_offset.to_i,
                start_char: value_for(span, :start_char).to_i,
                end_char: value_for(span, :end_char).to_i,
                chapter_source_path: value_for(entry, :chapter_source_path)
              }
            rescue Shoko::Error, ArgumentError => e
              @logger&.debug(
                'inline_link_navigator.link_hit_for_event_failed',
                error: e.class.name,
                message: e.message
              )
              nil
            end

            private

            def navigation_context_for(event)
              return nil unless left_click_release?(event)

              link_context_for(event)
            end

            def link_context_for(event)
              rendered = rendered_lines
              return nil unless rendered

              anchor = anchor_for_event(event, rendered)
              return nil unless anchor

              entry = rendered[anchor.geometry_key]
              geometry = entry && entry[:geometry]
              return nil unless geometry
              return nil unless point_within_geometry?(event, geometry)

              span = link_span_for_anchor(entry, geometry, anchor.cell_index)
              return nil unless span

              href = value_for(span, :href).to_s.strip
              return nil if href.nil? || href.empty?

              { href: href, entry: entry, geometry: geometry, span: span }
            end

            def rendered_lines
              rendered = @rendered_content_reader&.rendered_lines
              return nil unless rendered.is_a?(Hash) && !rendered.empty?

              rendered
            end

            def anchor_for_event(event, rendered)
              point = { x: event[:x], y: event[:y] }
              @coordinate_service.anchor_from_point(point, rendered, bias: :nearest)
            end

            def left_click_release?(event)
              button = event[:button].to_i
              event[:released] && button.nobits?(0b11) && button.nobits?(32)
            end

            def point_within_geometry?(event, geometry)
              row = event[:y].to_i + 1
              return false unless row == geometry.row.to_i

              width = geometry.visible_width.to_i
              return false if width <= 0

              col = event[:x].to_i + 1
              start_col = geometry.column_origin.to_i
              end_col = start_col + width - 1
              col.between?(start_col, end_col)
            end

            def link_span_for_anchor(entry, geometry, cell_index)
              spans = Array(value_for(entry, :link_spans))
              return nil if spans.empty? || geometry.nil?

              cells = Array(geometry.cells)
              index = cell_index.to_i
              return nil if index.negative? || index >= cells.length

              char_index = cells[index].char_start.to_i
              link_span_for_char(spans, char_index)
            end

            def link_span_for_char(spans, char_index)
              spans.find do |candidate|
                start_char = value_for(candidate, :start_char).to_i
                end_char = value_for(candidate, :end_char).to_i
                char_index >= start_char && char_index < end_char
              end
            end

            def destination_for(href, entry)
              chapter_index = target_chapter_index(href, entry)
              return nil unless chapter_index

              fragment = fragment_from_href(href)
              line_offset = if fragment
                              @anchor_resolver.line_offset_for_href(href: href, chapter_index: chapter_index)
                            else
                              0
                            end

              if line_offset.nil?
                return nil if chapter_index == current_chapter_index && fragment

                line_offset = 0
              end

              { chapter_index: chapter_index, line_offset: line_offset.to_i }
            end

            def target_chapter_index(href, entry)
              current = current_chapter_index
              core = core_href(href)
              return current if core.nil? || core.empty?
              return nil if external_href?(core)

              base = chapter_source_path_from_entry(entry) || chapter_source_path_for(current)
              target_path = resolve_target_path(core, base)
              return nil unless target_path

              chapter_index_for_path(target_path) || (same_path?(target_path, base) ? current : nil)
            end

            def core_href(href)
              value = href.to_s.strip
              return nil if value.empty?

              CGI.unescape(value.split('#', 2).first.to_s).strip
            end

            def fragment_from_href(href)
              fragment = href.to_s.split('#', 2)[1]
              return nil if fragment.nil?

              decoded = CGI.unescape(fragment.to_s).strip
              decoded.empty? ? nil : decoded
            end

            def external_href?(href)
              value = href.to_s.strip
              return false if value.empty?

              value.start_with?('//') || value.match?(/\A[a-z][a-z0-9+.-]*:/i)
            end

            def resolve_target_path(core, base_source_path)
              raw = core.to_s.strip
              return nil if raw.empty?

              return normalize_path(raw) if raw.start_with?('/')

              base = normalize_path(base_source_path)
              return normalize_path(raw) if base.nil? || base.empty?

              base_dir = File.dirname(base)
              normalize_path(File.expand_path(File.join('/', base_dir, raw), '/'))
            end

            def chapter_source_path_from_entry(entry)
              normalize_path(value_for(entry, :chapter_source_path))
            end

            def chapter_source_path_for(index)
              chapter = document_chapter(index)
              return nil unless chapter

              metadata = chapter.metadata || {}
              normalize_path(metadata[:source_path] || metadata['source_path'] || metadata[:href] || metadata['href'])
            end

            def chapter_index_for_path(path)
              normalized = normalize_path(path)
              return nil unless normalized

              map = chapter_index_map
              map[normalized] || map[normalized.downcase]
            end

            def chapter_index_map
              doc = document
              return {} unless doc

              cache_key = doc.object_id
              if @chapter_index_map_key != cache_key
                @chapter_index_map_key = cache_key
                @chapter_index_map = build_chapter_index_map(doc)
              end

              @chapter_index_map
            end

            def build_chapter_index_map(doc)
              chapters_for_document(doc).each_with_index.each_with_object({}) do |(chapter, idx), map|
                register_chapter_paths(map, chapter, idx)
              end
            end

            def chapters_for_document(doc)
              return Array(doc.chapters) if doc.respond_to?(:chapters)

              count = doc.respond_to?(:chapter_count) ? doc.chapter_count.to_i : 0
              Array.new(count) { |idx| doc.get_chapter(idx) }
            end

            def register_chapter_paths(map, chapter, idx)
              return unless chapter

              metadata = chapter.metadata || {}
              candidates = [
                metadata[:source_path], metadata['source_path'],
                metadata[:href], metadata['href']
              ]

              candidates.each do |candidate|
                normalized = normalize_path(candidate)
                next unless normalized

                map[normalized] ||= idx
                map[normalized.downcase] ||= idx
              end
            end

            def same_path?(path_a, path_b)
              norm_a = normalize_path(path_a)
              norm_b = normalize_path(path_b)
              return false unless norm_a && norm_b

              norm_a == norm_b || norm_a.casecmp?(norm_b)
            end

            def normalize_path(path)
              value = CGI.unescape(path.to_s).strip
              return nil if value.empty?

              value = value.split(/[?#]/, 2).first.to_s
              value = value.sub(%r{\A/+}, '')
              value.empty? ? nil : value
            end

            def current_chapter_index
              @reader_state_reader.current_chapter.to_i
            end

            def document
              @document_reader.call
            end

            def document_chapter(index)
              doc = document
              return nil unless doc

              if doc.respond_to?(:chapters)
                Array(doc.chapters)[index]
              else
                doc.get_chapter(index)
              end
            end

            def value_for(source, key)
              return nil unless source

              source[key] || source[key.to_s]
            end
          end
        end
      end
    end
  end
end
