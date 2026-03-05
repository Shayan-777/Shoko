# frozen_string_literal: true

require_relative 'pdf_reader'
require_relative 'pdf_content_stream_parser'
require_relative 'pdf_font_profile_resolver'

module Shoko
  module Core
    module BookFormats
      module Pdf
        # Extracts readable Unicode text and layout hints from PDF page content streams.
        class PdfTextExtractor
          # @param reader [PdfReader]
          def initialize(reader)
            @reader = reader
            @font_profile_resolver = PdfFontProfileResolver.new(reader: @reader)
          end

          # Extract text from a single page.
          # @param page_obj_num [Integer]
          # @return [String]
          def extract_page_text(page_obj_num)
            page_raw = @reader.read_object_raw(page_obj_num)
            return '' unless page_raw

            font_profiles = build_font_profiles(page_raw, page_obj_num)
            stream = read_page_content_stream(page_raw)
            return '' unless stream && !stream.empty?

            stream.force_encoding(Encoding::BINARY)
            raw_lines = parse_content_stream_lines(stream, font_profiles)
            assemble_paragraphs(raw_lines)
          rescue Shoko::Error => e
            raise Shoko::BookParseError.new("Failed to extract PDF page text for page #{page_obj_num}: #{e.message}",
                                            '')
          end

          # Extract line-level layout metadata for a page.
          #
          # @param page_obj_num [Integer]
          # @return [Array<Hash>] e.g. [{ text:, x:, italic: }]
          def extract_page_layout(page_obj_num)
            page_raw = @reader.read_object_raw(page_obj_num)
            return [] unless page_raw

            font_profiles = build_font_profiles(page_raw, page_obj_num)
            stream = read_page_content_stream(page_raw)
            return [] unless stream && !stream.empty?

            stream.force_encoding(Encoding::BINARY)
            parse_content_stream_lines(stream, font_profiles).map do |line|
              {
                text: line[:text].to_s,
                x: line[:x],
                italic: !!line[:italic],
                italic_ratio: line[:italic_ratio],
              }
            end
          rescue Shoko::Error => e
            raise Shoko::BookParseError.new("Failed to extract PDF layout for page #{page_obj_num}: #{e.message}", '')
          end

          private

          # Read the content stream(s) for a page.
          # /Contents can be a single stream reference or an array of references.
          # @return [String, nil]
          def read_page_content_stream(page_raw)
            content_val = @reader.dict_value(page_raw, 'Contents')
            return nil unless content_val

            refs = content_val.scan(/(\d+)\s+\d+\s+R/)
            return nil if refs.empty?

            return @reader.read_stream(refs[0][0].to_i) if refs.length == 1

            parts = refs.filter_map do |ref|
              @reader.read_stream(ref[0].to_i)
            end
            parts.empty? ? nil : parts.join(' '.b)
          end

          # @return [Hash<String, Hash>] font_name => { cmap:, italic:, base_font: }
          def build_font_profiles(page_raw, page_obj_num = nil)
            @font_profile_resolver.build_font_profiles(page_raw, page_obj_num)
          end

          # @return [Hash<String, Hash>] font_name => {glyph_id => unicode}
          def build_font_cmaps(page_raw, page_obj_num = nil)
            @font_profile_resolver.build_font_cmaps(page_raw, page_obj_num)
          end

          # @param stream [String]
          # @param font_profiles [Hash<String, Hash>]
          # @return [Array<Hash>] [{ text:, x:, italic:, italic_ratio: }]
          def parse_content_stream_lines(stream, font_profiles)
            PdfContentStreamParser.new(
              stream: stream,
              font_profiles: font_profiles
            ).parse
          end

          # Detect paragraph breaks from line indent changes.
          #
          # @param raw_lines [Array<Hash>]
          # @return [String]
          def assemble_paragraphs(raw_lines)
            return '' if raw_lines.empty?

            x_values = raw_lines.filter_map { |line| line[:x]&.round(0) }
            baseline_x = x_values.min || 0

            result = +''
            raw_lines.each do |line|
              text = line[:text]
              x = line[:x]
              next if text.strip.empty?

              if !result.empty? && x && (x - baseline_x) > 5
                result << "\n\n" << text.strip
              elsif result.empty?
                result << text.strip
              else
                result << "\n" << text.strip
              end
            end
            result
          end
        end
      end
    end
  end
end
