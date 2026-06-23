# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/shoko/adapters/book_sources/pdf/parser/pdf_text_extractor'

RSpec.describe Shoko::Adapters::BookSources::Pdf::PdfTextExtractor do
  let(:reader) do
    Class.new do
      page_raw = '1 0 obj << /Resources 30 0 R /Contents 20 0 R >> endobj'
      resources_raw = '30 0 obj << /Font 40 0 R >> endobj'
      font_map_raw = '40 0 obj << /F1 10 0 R >> endobj'
      font_raw = '10 0 obj << /BaseFont /Times-Roman /ToUnicode 50 0 R >> endobj'
      tounicode_stream = <<~CMAP
        /CIDInit /ProcSet findresource begin
        12 dict begin
        begincmap
        1 begincodespacerange
        <00> <FF>
        endcodespacerange
        1 beginbfchar
        <01> <0069006E>
        endbfchar
        endcmap
        CMapName currentdict /CMap defineresource pop
        end
        end
      CMAP
      stream = "BT /F1 12 Tf 72 700 Td (\x01) Tj ET".b

      define_method(:read_object_raw) do |obj_num|
        case obj_num
        when 1 then page_raw
        when 30 then resources_raw
        when 40 then font_map_raw
        when 10 then font_raw
        end
      end

      define_method(:dict_value) do |dict_text, key|
        case key
        when 'Resources'
          return '30 0 R' if dict_text == page_raw
        when 'Contents'
          return '20 0 R' if dict_text == page_raw
        when 'Font'
          return '40 0 R' if dict_text == resources_raw
        when 'BaseFont'
          return 'Times-Roman' if dict_text == font_raw
        when 'ToUnicode'
          return '50 0 R' if dict_text == font_raw
        when 'FontDescriptor'
          return nil
        end

        nil
      end

      define_method(:resolve_ref) do |ref_string|
        match = ref_string.to_s.match(/(\d+)\s+\d+\s+R/)
        match ? match[1].to_i : nil
      end

      define_method(:read_stream) do |obj_num|
        case obj_num
        when 20 then stream
        when 50 then tounicode_stream
        end
      end
    end.new
  end

  it 'decodes literal glyph bytes through indirect font resources and multi-character ToUnicode mappings' do
    extractor = described_class.new(reader)

    expect(extractor.extract_page_text(1)).to eq('in')
    expect(extractor.extract_page_layout(1)).to eq(
      [{ text: 'in', x: 72.0, y: 700.0, italic: false, italic_ratio: 0.0, bold: false, font_size: 12.0 }]
    )
  end
end
