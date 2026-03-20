# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Fb2
        class Fb2Importer
          # Builds chapter, TOC, and resource payloads from a parsed FB2 document.
          module DocumentBuilding
            private

            def build_book_data(metadata, chapters, resources)
              report('Building table of contents...', progress: 0.7)
              toc_entries = build_toc_entries(chapters)
              report('Finalizing...', progress: 0.9)
              Core::Models::BookData.new(**book_data_attributes(metadata, chapters, toc_entries, resources))
            end

            def book_data_attributes(metadata, chapters, toc_entries, resources)
              {
                title: metadata[:title] || fallback_title(@fb2_path),
                language: metadata[:language] || DEFAULT_LANGUAGE,
                authors: Array(metadata[:authors]).map(&:to_s),
                chapters: chapters,
                toc_entries: toc_entries,
                opf_path: nil,
                spine: [],
                chapter_hrefs: [],
                resources: resources,
                metadata: metadata,
                container_path: nil,
                container_xml: nil,
                format_data: { format: :fb2, source_type: detect_source_type(@fb2_path) },
              }
            end

            def build_chapters(doc)
              bodies = collect_bodies(doc)
              return [error_chapter('No content found')] if bodies.empty?

              chapters = []
              Array(bodies).each_with_index { |body, body_index| append_body_chapters(chapters, body, body_index) }
              chapters.empty? ? [error_chapter('No chapters found')] : chapters
            end

            def append_body_chapters(chapters, body, body_index)
              context = body_chapter_context(body)
              Array(context[:sections]).each_with_index do |section, index|
                report_body_progress(index + 1, context[:total], chapters.length + 1)
                chapters << build_chapter_from_section(section, chapters.length + 1, body_index, context[:notes])
              end
            end

            def body_chapter_context(body)
              sections = Adapters::BookSources::Fb2::Fb2SectionFlattener.flatten(body)
              { sections: sections, total: sections.length, notes: notes_body?(body) }
            end

            def notes_body?(body)
              body.attributes['name'].to_s.casecmp('notes').zero?
            end

            def report_body_progress(index, total, chapter_number)
              report("Building chapter #{chapter_number}...", progress: 0.3 + (0.4 * ratio(index, total)))
            end

            def build_chapter_from_section(section, chapter_number, body_index, notes_body)
              Core::Models::Chapter.new(
                number: chapter_number.to_s,
                title: sanitize(resolved_section_title(section, chapter_number, notes_body)),
                lines: nil,
                metadata: { format: :fb2, section_depth: section.depth, body_index: body_index },
                blocks: nil,
                raw_content: section_to_xml(section.element)
              )
            end

            def resolved_section_title(section, chapter_number, notes_body)
              title = section.title
              return 'Notes' if title.nil? && notes_body

              text = title.to_s.strip
              text.empty? ? "Chapter #{chapter_number}" : text
            end

            def build_toc_entries(chapters)
              Array(chapters).each_with_index.map do |chapter, index|
                Core::Models::TOCEntry.new(
                  title: chapter.title || "Chapter #{index + 1}",
                  href: nil,
                  level: chapter.metadata.is_a?(Hash) ? (chapter.metadata[:section_depth] || 0) : 0,
                  chapter_index: index,
                  navigable: true
                )
              end
            end

            def extract_binary_resources(doc)
              binary_elements(doc).each_with_object({}) do |element, resources|
                decoded = decoded_binary_resource(element)
                next unless decoded

                resources[decoded[:id]] = decoded[:data]
              end
            end

            def binary_elements(doc)
              root = doc.root || doc
              root.elements.select { |child| child.name.to_s.casecmp('binary').zero? }
            end

            def decoded_binary_resource(element)
              id = element.attributes['id'].to_s.strip
              return nil if id.empty?

              base64_data = element.text.to_s.gsub(/\s+/, '')
              return nil if base64_data.empty?

              decoded = Base64.decode64(base64_data)
              decoded.force_encoding(Encoding::BINARY)
              { id: id, data: decoded }
            end

            def collect_bodies(doc)
              bodies = direct_body_children(doc)
              return bodies unless bodies.empty?

              doc.elements.to_a('//body')
            end

            def direct_body_children(doc)
              root = doc.root || doc
              root.elements.select { |child| child.name.to_s.casecmp('body').zero? }
            end

            def section_to_xml(element)
              return '' unless element

              output = +''
              REXML::Formatters::Default.new.write(element, output)
              output
            rescue Shoko::Error
              element.to_s
            end

            def error_chapter(message)
              Core::Models::Chapter.new(
                number: '1',
                title: 'Error',
                lines: [message],
                metadata: { format: :fb2 },
                blocks: nil,
                raw_content: nil
              )
            end

            def sanitize(text)
              Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
            rescue Shoko::Error
              text.to_s
            end
          end
        end
      end
    end
  end
end
