# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Rtf
        # Canonical parser for RTF metadata and content-based fallbacks.
        class MetadataParser
          class << self
            # @param doc [Object] Parsed RTF document
            # @param fallback_title [String] Fallback title from file name
            # @return [Hash] canonical metadata hash
            def parse(doc:, fallback_title:)
              metadata = empty_metadata
              extract_from_info(doc&.info, metadata)
              extract_from_content(doc, metadata)
              finalize_metadata(metadata, fallback_title)
            rescue Shoko::Error
              fallback_metadata(fallback_title)
            end

            private

            def empty_metadata
              { title: nil, authors: [], year: nil, language: nil }
            end

            def finalize_metadata(metadata, fallback_title)
              metadata[:title] ||= normalize_text(fallback_title)
              metadata[:authors] = normalize_authors(metadata[:authors])
              metadata
            end

            def fallback_metadata(fallback_title)
              empty_metadata.merge(title: normalize_text(fallback_title))
            end

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
              candidates = ranked_candidates(doc)
              return { title: nil, authors: [] } if candidates.empty?

              title = candidates.first[:text]
              { title: title, authors: inferred_authors(candidates, title) }
            end

            def build_candidates(paragraphs)
              Array(paragraphs).first(30).filter_map { |paragraph| build_candidate(paragraph) }
            end

            def ranked_candidates(doc)
              build_candidates(doc&.paragraphs).sort_by do |candidate|
                [-candidate[:font_size], -candidate[:text].length]
              end
            end

            def build_candidate(paragraph)
              runs = Array(paragraph.runs)
              text = candidate_text(paragraph, runs)
              return nil unless text

              { text: text, font_size: runs.map { |run| run.font_size || 24 }.max, bold: runs.all?(&:bold) }
            end

            def inferred_authors(candidates, title)
              match = Array(candidates).find { |candidate| author_candidate?(candidate, title) }
              match ? [match[:text]] : []
            end

            def author_candidate?(candidate, title)
              candidate[:text] != title &&
                candidate[:bold] &&
                !candidate[:text].start_with?('[') &&
                !candidate[:text].match?(/\A\(\d{4}/)
            end

            def candidate_text(paragraph, runs)
              return nil if runs.empty? || paragraph.alignment != :center

              text = normalize_text(runs.map(&:text).join)
              return nil unless text && text.length >= 2

              text
            end

            def normalize_authors(authors)
              Array(authors).filter_map { |value| normalize_text(value) }
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
  end
end
