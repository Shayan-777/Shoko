# frozen_string_literal: true

module Shoko
  module Core::BookFormats::Rtf
    # Canonical parser for RTF metadata and content-based fallbacks.
    class MetadataParser
      class << self
        # @param doc [Object] Parsed RTF document
        # @param fallback_title [String] Fallback title from file name
        # @return [Hash] canonical metadata hash
        def parse(doc:, fallback_title:)
          metadata = {
            title: nil,
            authors: [],
            year: nil,
            language: nil,
          }

          extract_from_info(doc&.info, metadata)
          extract_from_content(doc, metadata)
          metadata[:title] ||= normalize_text(fallback_title)
          metadata[:authors] = normalize_authors(metadata[:authors])
          metadata
        rescue StandardError
          {
            title: normalize_text(fallback_title),
            authors: [],
            year: nil,
            language: nil,
          }
        end

        private

        def extract_from_info(info, metadata)
          return unless info

          raw_title = normalize_text(info.title)
          raw_author = normalize_text(info.author)

          info_unreliable = invalid_title?(raw_title)
          metadata[:title] = raw_title unless info_unreliable
          metadata[:authors] = [raw_author] if raw_author && !info_unreliable

          year_match = info.creatim.to_s.match(/(\d{4})/)
          metadata[:year] = year_match[1] if year_match
        end

        def extract_from_content(doc, metadata)
          return unless metadata[:title].nil? || metadata[:authors].empty?

          content_meta = infer_from_content(doc)
          metadata[:title] ||= content_meta[:title]
          metadata[:authors] = content_meta[:authors] if metadata[:authors].empty?
        end

        def invalid_title?(title)
          return true if title.nil? || title.empty?
          return true if title.length < 3
          return true if title.start_with?('[')
          return true if title.match?(/\A(Version|Draft|Document|Untitled)/i)

          false
        end

        def infer_from_content(doc)
          result = { title: nil, authors: [] }
          paragraphs = Array(doc&.paragraphs)
          return result if paragraphs.empty?

          candidates = build_candidates(paragraphs)
          return result if candidates.empty?

          sorted = candidates.sort_by { |candidate| [-candidate[:font_size], -candidate[:text].length] }
          result[:title] = sorted[0][:text]

          sorted.each do |candidate|
            next if candidate[:text] == result[:title]
            next unless candidate[:bold]
            next if candidate[:text].match?(/\A\[/)
            next if candidate[:text].match?(/\A\(\d{4}/)

            result[:authors] = [candidate[:text]]
            break
          end

          result
        end

        def build_candidates(paragraphs)
          paragraphs.first(30).each_with_object([]) do |paragraph, acc|
            next if Array(paragraph.runs).empty?
            next unless paragraph.alignment == :center

            text = normalize_text(paragraph.runs.map(&:text).join)
            next unless text && text.length >= 2

            max_size = paragraph.runs.map { |run| run.font_size || 24 }.max
            all_bold = paragraph.runs.all?(&:bold)
            acc << { text: text, font_size: max_size, bold: all_bold }
          end
        end

        def normalize_authors(authors)
          Array(authors).map { |value| normalize_text(value) }.compact
        end

        def normalize_text(value)
          return nil unless value

          text = value.to_s.strip
          text.empty? ? nil : text
        end
      end
    end
  end
end
