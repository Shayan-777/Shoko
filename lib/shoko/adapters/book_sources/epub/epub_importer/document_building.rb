# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Epub
        class EpubImporter
          # Chapter, TOC, and book-data assembly helpers.
          module DocumentBuilding
            private

            def build_chapters(zip, opf_path, items)
              report_initial_chapter_progress(items.length)

              items.each_with_index.with_object({ chapters: [], hrefs: [], spine: [] }) do |(item, index), acc|
                report_chapter_progress(index, items.length)
                chapter = chapter_from_item(zip, opf_path, item)
                append_chapter(acc, chapter, item.file_path)
              end
            end

            def spine_items(processor, manifest, chapter_titles)
              items = []
              processor.process_spine(manifest, chapter_titles) { |item| items << item }
              items
            end

            def report_initial_chapter_progress(total)
              message = if total.positive?
                          "Extracting HTML (0/#{total})..."
                        else
                          'Extracting HTML...'
                        end
              report(message, progress: 0.0)
            end

            def report_chapter_progress(index, total)
              report(
                "Extracting HTML (#{index + 1}/#{total})...",
                progress: ratio(index + 1, total)
              )
            end

            def append_chapter(acc, chapter, spine_path)
              acc[:chapters] << chapter
              acc[:hrefs] << chapter.metadata[:href]
              acc[:spine] << spine_path
            end

            def chapter_from_item(zip, opf_path, item)
              raw = read_text_entry(zip, item.file_path)
              resolved_href = resolve_href(opf_path, item.href)
              Core::Models::Chapter.new(
                number: item.number.to_s,
                title: extract_chapter_title(raw, item.number, item.title),
                lines: nil,
                metadata: { source_path: item.file_path, href: resolved_href },
                blocks: nil,
                raw_content: raw
              )
            end

            def build_toc_entries(chapters, toc_entries, chapter_hrefs, opf_path)
              href_to_index = chapter_href_index(chapter_hrefs)

              Array(toc_entries).map do |entry|
                build_toc_entry(chapters, href_to_index, opf_path, entry)
              end
            end

            def chapter_href_index(chapter_hrefs)
              chapter_hrefs.each_with_index.with_object({}) do |(href, index), mapping|
                mapping[href] = index if href
              end
            end

            def build_toc_entry(chapters, href_to_index, opf_path, entry)
              title = entry[:title]
              href = entry[:href]
              level = entry[:level].to_i
              chapter_index = href_to_index[resolve_toc_target(opf_path, entry)]
              apply_toc_title!(chapters, chapter_index, title)

              Core::Models::TOCEntry.new(
                title: title,
                href: href,
                level: level,
                chapter_index: chapter_index,
                navigable: !chapter_index.nil?
              )
            end

            def apply_toc_title!(chapters, chapter_index, title)
              return unless chapter_index

              chapter = chapters[chapter_index]
              chapter.title = title if chapter && chapter.title.to_s.strip.empty?
            end

            def resolve_toc_target(opf_path, entry)
              return nil unless entry
              return entry[:target].to_s if entry.is_a?(Hash) && entry[:target]

              href = entry.is_a?(Hash) ? entry[:href] : nil
              core_href = href.to_s.split('#', 2).first
              return nil if core_href.empty?

              base_path = toc_source_path(entry, opf_path)
              base_dir = File.dirname(base_path)
              File.expand_path(File.join('/', base_dir, core_href), '/').sub(%r{^/}, '')
            end

            def toc_source_path(entry, opf_path)
              source_path = entry.is_a?(Hash) ? entry[:source_path] : nil
              (source_path || opf_path).to_s
            end

            def build_book_data(metadata:, chapters:, toc_entries:, opf_path:, spine:, chapter_hrefs:, resources:,
                                container_xml:)
              Core::Models::BookData.new(
                title: metadata[:title] || fallback_title(@epub_path),
                language: metadata[:language] || DEFAULT_LANGUAGE,
                authors: Array(metadata[:authors]).map(&:to_s),
                chapters: chapters,
                toc_entries: toc_entries,
                opf_path: opf_path,
                spine: spine,
                chapter_hrefs: chapter_hrefs,
                resources: resources,
                metadata: metadata,
                container_path: CONTAINER_PATH,
                container_xml: container_xml
              )
            end
          end
        end
      end
    end
  end
end
