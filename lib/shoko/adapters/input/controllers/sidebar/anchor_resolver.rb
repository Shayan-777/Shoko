# frozen_string_literal: true

require 'cgi'
require_relative '../../../../application/ports/outbound/formatting/display_line'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          # Resolves TOC href anchors into chapter line offsets.
          class AnchorResolver
            SUPERSCRIPT_DIGITS = {
              '⁰' => '0',
              '¹' => '1',
              '²' => '2',
              '³' => '3',
              '⁴' => '4',
              '⁵' => '5',
              '⁶' => '6',
              '⁷' => '7',
              '⁸' => '8',
              '⁹' => '9',
            }.freeze

            SUBSCRIPT_DIGITS = {
              '₀' => '0',
              '₁' => '1',
              '₂' => '2',
              '₃' => '3',
              '₄' => '4',
              '₅' => '5',
              '₆' => '6',
              '₇' => '7',
              '₈' => '8',
              '₉' => '9',
            }.freeze

            def initialize(document_reader:, formatting_service:, layout_service:, ui_state_reader:, config_reader:,
                           sidebar_state_reader:)
              @document_reader = document_reader
              @formatting_service = formatting_service
              @layout_service = layout_service
              @ui_state_reader = ui_state_reader
              @config_reader = config_reader
              @sidebar_state_reader = sidebar_state_reader
            end

            def line_offset_for_toc_entry(entry, chapter_index)
              line_offset_for_href(href: entry&.href, chapter_index: chapter_index)
            end

            def line_offset_for_href(href:, chapter_index:)
              anchor = anchor_from_href(href)
              return nil if anchor.nil? || anchor.empty?

              lines = wrapped_lines_for_anchor(chapter_index)
              return nil if lines.nil? || lines.empty?

              best_anchor_match_line(lines, anchor_match_indices(lines, anchor), anchor)
            end

            def anchor_from_href(href)
              return nil if href.nil?

              fragment = href.to_s.split('#', 2)[1]
              return nil if fragment.nil? || fragment.empty?

              CGI.unescape(fragment.to_s).strip
            end

            private

            def wrapped_lines_for_anchor(chapter_index)
              return nil unless anchor_wrap_ready?

              col_width, lines_per_page = anchor_wrap_metrics
              @formatting_service.wrap_all(
                document,
                chapter_index,
                col_width,
                config: @config_reader,
                lines_per_page: lines_per_page
              )
            end

            def document
              @document_reader.call
            end

            def anchors_match?(anchors, anchor, anchor_down)
              anchors.include?(anchor) ||
                anchors.any? { |value| value.casecmp?(anchor) } ||
                anchors.any? { |value| value.downcase == anchor_down }
            end

            def anchor_match_indices(lines, anchor)
              anchor_down = anchor.downcase

              lines.each_with_index.filter_map do |line, idx|
                next unless line.is_a?(Shoko::Application::Ports::Outbound::Formatting::DisplayLine)

                anchors = line_anchors(line)
                next unless anchors_match?(anchors, anchor, anchor_down)

                idx
              end
            end

            def line_anchors(line)
              anchors = line.metadata[:anchors] || line.metadata['anchors']
              Array(anchors).map(&:to_s)
            end

            def best_anchor_match_line(lines, matches, anchor)
              return nil if matches.empty?
              return matches.first if matches.length == 1

              token = numeric_anchor_token(anchor)
              return nil unless token

              prefer_line_with_token(lines, matches, token)
            end

            def numeric_anchor_token(anchor)
              tokens = anchor.to_s.scan(/\d+/)
              token = tokens.last
              return nil if token.nil? || token.empty?

              token
            end

            def prefer_line_with_token(lines, matches, token)
              strict = /\A\s*[\[(]?#{Regexp.escape(token)}(?:[\]).:-]|\b)/i
              relaxed = /\b#{Regexp.escape(token)}\b/i

              matches.find { |idx| normalized_line_text(lines[idx]).match?(strict) } ||
                matches.find { |idx| normalized_line_text(lines[idx]).match?(relaxed) }
            end

            def line_text(line)
              return '' unless line

              line.text.to_s
            end

            def normalized_line_text(line)
              text = line_text(line)
              return '' if text.empty?

              text.each_char.map { |char| SUPERSCRIPT_DIGITS[char] || SUBSCRIPT_DIGITS[char] || char }.join
            end

            def anchor_wrap_ready?
              @formatting_service && @layout_service && document
            end

            def anchor_wrap_metrics
              width, height = terminal_dimensions
              effective_width = @layout_service.effective_content_width(width, sidebar_visible: sidebar_visible?)
              col_width, content_height = @layout_service.calculate_metrics(effective_width, height, view_mode)
              [col_width, @layout_service.adjust_for_line_spacing(content_height, line_spacing)]
            end

            def terminal_dimensions
              [(@ui_state_reader&.terminal_width || 80).to_i, (@ui_state_reader&.terminal_height || 24).to_i]
            end

            def view_mode
              @config_reader&.view_mode || :single
            end

            def line_spacing
              @config_reader&.line_spacing || :normal
            end

            def sidebar_visible?
              @sidebar_state_reader&.sidebar_visible? == true
            end
          end
        end
      end
    end
  end
end
