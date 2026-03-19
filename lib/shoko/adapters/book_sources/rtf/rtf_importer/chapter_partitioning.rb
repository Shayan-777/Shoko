# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Rtf
        class RtfImporter
          # Splits parsed RTF paragraphs into chapter groups using page-break and heading heuristics.
          module ChapterPartitioning
            private

            def split_into_chapters(doc)
              paragraphs = Array(doc.paragraphs)
              page_break_groups = split_by_page_breaks(paragraphs)
              return page_break_groups if page_break_groups.length > 1

              heading_groups = split_by_headings(paragraphs)
              return heading_groups if heading_groups.length > 1

              [build_chapter_group(paragraphs)]
            end

            def split_by_page_breaks(paragraphs)
              groups = []
              current = []

              Array(paragraphs).each do |paragraph|
                append_page_break_group(groups, current) if paragraph.page_break_before && !current.empty?
                current << paragraph
              end

              append_page_break_group(groups, current)
              groups
            end

            def append_page_break_group(groups, paragraphs)
              return if paragraphs.empty?

              groups << build_chapter_group(paragraphs)
              paragraphs.clear
            end

            def split_by_headings(paragraphs)
              groups = []
              current = []
              heading = { title: nil, level: 0 }

              Array(paragraphs).each do |paragraph|
                heading_type = detect_heading(paragraph)
                if heading_type
                  append_heading_group(groups, current, heading)
                  current = [paragraph]
                  heading = heading_state(paragraph, heading_type)
                else
                  current << paragraph
                end
              end

              append_heading_group(groups, current, heading)
              groups
            end

            def append_heading_group(groups, paragraphs, heading)
              return if heading[:title].nil? && paragraphs.empty?

              groups << build_chapter_group(paragraphs, title: heading[:title], level: heading[:level])
            end

            def heading_state(paragraph, heading_type)
              {
                title: paragraph_text(paragraph),
                level: heading_type == :volume ? 0 : 1,
              }
            end

            def build_chapter_group(paragraphs, title: nil, level: 0)
              {
                title: title || extract_title(paragraphs),
                paragraphs: Array(paragraphs).dup,
                level: level,
              }
            end

            def detect_heading(paragraph)
              return nil unless centered_bold_paragraph?(paragraph)

              text = paragraph_text(paragraph)
              return :volume if text.match?(VOLUME_HEADING)
              return :chapter if text.match?(CHAPTER_HEADING)

              nil
            end

            def centered_bold_paragraph?(paragraph)
              runs = Array(paragraph.runs)
              runs.any? && paragraph.alignment == :center && runs.all?(&:bold)
            end

            def extract_title(paragraphs)
              Array(paragraphs).first(5).each do |paragraph|
                text = paragraph_text(paragraph)
                return text unless text.empty?
              end

              'Untitled'
            end

            def paragraph_text(paragraph)
              Array(paragraph.runs).map(&:text).join.strip
            end
          end
        end
      end
    end
  end
end
