# frozen_string_literal: true

require_relative 'rtf_parser'

module Shoko
  module Core::BookFormats::Rtf
    # Lightweight metadata extractor for RTF files.
    # Implements the self.from_file(path) interface used by FormatRegistry.
    module RtfMetadataExtractor
      class << self
        # @param path [String] path to RTF file
        # @param file_probe [#file?, nil] file probe dependency
        # @param file_reader [#call, nil] binary file reader
        # @param path_ops [#basename, nil] path utility dependency
        # @return [Hash] metadata hash with :title, :authors, :author_str, :year, :language
        def from_file(path, file_probe: nil, file_reader: nil, path_ops: nil, **_)
          return {} unless file_probe&.file?(path)
          return {} unless file_reader

          raw = file_reader.call(path).to_s.force_encoding('BINARY')
          content = raw.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

          doc = RtfParser.new(content).parse
          info = doc.info

          metadata = {
            title: nil,
            authors: [],
            author_str: nil,
            year: nil,
            language: nil
          }

          # Extract from \info fields
          info_unreliable = false
          if info
            raw_title = info.title.to_s.strip
            raw_author = info.author.to_s.strip

            if invalid_title?(raw_title)
              # If title is invalid, the whole \info is likely unreliable
              info_unreliable = true
            else
              metadata[:title] = raw_title
            end

            unless raw_author.empty? || info_unreliable
              metadata[:authors] = [raw_author]
            end

            if info.creatim
              year_match = info.creatim.to_s.match(/(\d{4})/)
              metadata[:year] = year_match[1] if year_match
            end
          end

          # Content fallback for title/author
          if metadata[:title].nil? || metadata[:authors].empty?
            content_meta = extract_from_content(doc)
            metadata[:title] ||= content_meta[:title]
            metadata[:authors] = content_meta[:authors] if metadata[:authors].empty?
          end

          # Final fallback: filename
          metadata[:title] ||= fallback_title(path, path_ops: path_ops)

          metadata[:author_str] = metadata[:authors].join('; ') unless metadata[:authors].empty?
          metadata.compact
        rescue StandardError
          {}
        end

        private

        def invalid_title?(title)
          return true if title.empty?
          return true if title.length < 3
          return true if title.start_with?('[')
          return true if title.match?(/\A(Version|Draft|Document|Untitled)/i)

          false
        end

        def extract_from_content(doc)
          result = { title: nil, authors: [] }
          paragraphs = doc.paragraphs
          return result if paragraphs.empty?

          # Look at first ~30 paragraphs for large-font centered text
          candidates = []
          paragraphs.first(30).each do |para|
            next if para.runs.empty?
            next unless para.alignment == :center

            text = para.runs.map(&:text).join.strip
            next if text.empty?
            next if text.length < 2

            max_fs = para.runs.map { |r| r.font_size || 24 }.max
            all_bold = para.runs.all?(&:bold)

            candidates << { text: text, font_size: max_fs, bold: all_bold }
          end

          return result if candidates.empty?

          # Title = largest font centered text
          sorted = candidates.sort_by { |c| [-c[:font_size], -c[:text].length] }

          if sorted.length >= 1
            result[:title] = sorted[0][:text]
          end

          # Author = second entry that is bold and different from title
          sorted.each do |c|
            next if c[:text] == result[:title]
            next unless c[:bold]
            next if c[:text].match?(/\A\[/)      # skip bracketed meta text
            next if c[:text].match?(/\A\(\d{4}/) # skip year markers

            result[:authors] = [c[:text]]
            break
          end

          result
        end

        def fallback_title(path, path_ops: nil)
          basename = basename_for(path, path_ops: path_ops).sub(/\.[^.]+\z/, '')
          # Try to extract title from "Title (Author).rtf" pattern
          if (m = basename.match(/\A(.+?)\s*\(.*\)\s*\z/))
            m[1].strip
          else
            basename.tr('_', ' ').strip
          end
        end

        def basename_for(path, path_ops: nil)
          if path_ops&.respond_to?(:basename)
            path_ops.basename(path).to_s
          else
            path.to_s.split(%r{[\\/]}).last.to_s
          end
        end
      end
    end
  end
end
