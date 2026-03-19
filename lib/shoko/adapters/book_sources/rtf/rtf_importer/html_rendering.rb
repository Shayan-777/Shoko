# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Rtf
        class RtfImporter
          # Converts parsed RTF paragraphs into chapter HTML and TOC structures.
          module HtmlRendering
            private

            def build_chapters(chapter_groups)
              Array(chapter_groups).each_with_index.map do |group, index|
                Core::Models::Chapter.new(
                  number: (index + 1).to_s,
                  title: group[:title],
                  lines: nil,
                  metadata: { format: :rtf, level: group[:level] },
                  blocks: nil,
                  raw_content: paragraphs_to_html(group[:paragraphs])
                )
              end
            end

            def build_toc_entries(chapters)
              Array(chapters).each_with_index.map do |chapter, index|
                Core::Models::TOCEntry.new(
                  title: chapter.title || "Chapter #{index + 1}",
                  href: nil,
                  level: chapter.metadata[:level] || 0,
                  chapter_index: index,
                  navigable: true
                )
              end
            end

            def paragraphs_to_html(paragraphs)
              html = +'<html><body>'
              Array(paragraphs).each { |paragraph| html << paragraph_to_html(paragraph) }
              html << '</body></html>'
            end

            def paragraph_to_html(paragraph)
              return '' unless paragraph_has_text?(paragraph)

              tag = paragraph_tag(paragraph)
              attrs = alignment_attr(paragraph.alignment)
              inner = Array(paragraph.runs).map { |run| run_to_html(run) }.join
              "<#{tag}#{attrs}>#{inner}</#{tag}>"
            end

            def paragraph_has_text?(paragraph)
              Array(paragraph.runs).any? && paragraph_text(paragraph).length.positive?
            end

            def paragraph_tag(paragraph)
              max_font_size = Array(paragraph.runs).map { |run| run.font_size || 24 }.max
              return 'h1' if max_font_size >= 48
              return 'h2' if max_font_size >= 36
              return 'h3' if max_font_size >= 28 && paragraph.alignment == :center

              'p'
            end

            def run_to_html(run)
              text = escape_html(run.text)
              return '' if text.empty?

              apply_run_wrappers(text, run)
            end

            def apply_run_wrappers(text, run)
              wrapped = text
              wrapped = "<sub>#{wrapped}</sub>" if run.subscript
              wrapped = "<sup>#{wrapped}</sup>" if run.superscript
              wrapped = "<s>#{wrapped}</s>" if run.strikethrough
              wrapped = "<u>#{wrapped}</u>" if run.underline
              wrapped = "<i>#{wrapped}</i>" if run.italic
              wrapped = "<b>#{wrapped}</b>" if run.bold
              wrapped
            end

            def alignment_attr(alignment)
              case alignment
              when :center
                ' style="text-align:center"'
              when :right
                ' style="text-align:right"'
              when :justify
                ' style="text-align:justify"'
              else
                ''
              end
            end

            def escape_html(text)
              text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
            end
          end
        end
      end
    end
  end
end
