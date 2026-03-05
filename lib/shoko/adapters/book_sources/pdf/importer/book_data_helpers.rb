# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        module Importer
          # BookData, TOC, and chapter range helpers used by PdfImporter.
          module BookDataHelpers
            private

            def build_book_data(metadata, chapters, toc_entries)
              report('Finalizing...', progress: 0.9)
              Core::Models::BookData.new(**book_data_attributes(metadata, chapters, toc_entries))
            end

            def book_data_attributes(metadata, chapters, toc_entries)
              {
                title: metadata[:title] || fallback_title(@pdf_path),
                language: metadata[:language] || PdfImporter::DEFAULT_LANGUAGE,
                authors: Array(metadata[:authors]).map(&:to_s),
                chapters: chapters,
                toc_entries: toc_entries,
                opf_path: nil,
                spine: [],
                chapter_hrefs: [],
                resources: {},
                metadata: metadata,
                container_path: nil,
                container_xml: nil,
                format_data: { format: :pdf },
              }
            end

            def build_toc_entries(outlines, chapters)
              return toc_entries_from_chapters(chapters) if outlines.empty?

              toc_entries_from_outlines(outlines)
            end

            def toc_entries_from_chapters(chapters)
              chapters.each_with_index.map do |chapter, idx|
                Core::Models::TOCEntry.new(
                  title: chapter.title,
                  href: nil,
                  level: 0,
                  chapter_index: idx,
                  navigable: true
                )
              end
            end

            def toc_entries_from_outlines(outlines)
              outlines.each_with_index.map do |entry, idx|
                Core::Models::TOCEntry.new(
                  title: sanitize(entry[:title] || "Chapter #{idx + 1}"),
                  href: nil,
                  level: entry[:depth] || 0,
                  chapter_index: idx,
                  navigable: true
                )
              end
            end

            def chapter_ranges(total_pages)
              ranges = []
              (0...total_pages).step(PdfImporter::PAGES_PER_AUTO_CHAPTER) do |start_page|
                end_page = [start_page + PdfImporter::PAGES_PER_AUTO_CHAPTER - 1, total_pages - 1].min
                ranges << [start_page, end_page]
              end
              ranges
            end

            def auto_chapter_progress(start_page, total_pages)
              0.3 + (0.6 * (start_page.to_f / [total_pages, 1].max))
            end
          end
        end
      end
    end
  end
end
