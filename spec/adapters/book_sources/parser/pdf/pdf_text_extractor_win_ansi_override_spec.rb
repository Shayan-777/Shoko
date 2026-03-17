# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/shoko/adapters/book_sources/pdf/parser/pdf_text_extractor'

class FakeWinAnsiOverrideReader
  PAGE_RAW = '1 0 obj << /Resources 30 0 R /Contents 20 0 R >> endobj'
  RESOURCES_RAW = '30 0 obj << /Font << /F1 10 0 R >> >> endobj'
  FONT_RAW = '10 0 obj << /BaseFont /SubsetFont /Subtype /Type1 /Encoding 40 0 R /ToUnicode 50 0 R >> endobj'
  ENCODING_RAW = '40 0 obj << /Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences [31 /f_i] >> endobj'
  TOUNICODE_STREAM = <<~CMAP
    /CIDInit /ProcSet findresource begin
    12 dict begin
    begincmap
    1 begincodespacerange
    <1F> <7A>
    endcodespacerange
    2 beginbfchar
    <1F> <00660069>
    <48> <004A>
    endbfchar
    1 beginbfrange
    <41> <7A> <0043>
    endbfrange
    endcmap
    CMapName currentdict /CMap defineresource pop
    end
    end
  CMAP
  STREAM = 'BT /F1 12 Tf 72 700 Td (He con\037nes himself to redistribution.) Tj ET'.b

  def read_object_raw(obj_num)
    case obj_num
    when 1 then PAGE_RAW
    when 30 then RESOURCES_RAW
    when 10 then FONT_RAW
    when 40 then ENCODING_RAW
    end
  end

  def dict_value(dict_text, key)
    case key
    when 'Resources'
      return '30 0 R' if dict_text == PAGE_RAW
    when 'Contents'
      return '20 0 R' if dict_text == PAGE_RAW
    when 'BaseFont'
      return 'SubsetFont' if dict_text == FONT_RAW
    when 'Encoding'
      return '40 0 R' if dict_text == FONT_RAW
    when 'BaseEncoding'
      return 'WinAnsiEncoding' if dict_text == ENCODING_RAW
    when 'ToUnicode'
      return '50 0 R' if dict_text == FONT_RAW
    when 'FontDescriptor'
      return nil
    end
    nil
  end

  def resolve_ref(ref_string)
    match = ref_string.to_s.match(/(\d+)\s+\d+\s+R/)
    match ? match[1].to_i : nil
  end

  def read_stream(obj_num)
    case obj_num
    when 20 then STREAM
    when 50 then TOUNICODE_STREAM
    end
  end
end

RSpec.describe Shoko::Adapters::BookSources::Pdf::PdfTextExtractor do
  it 'prefers WinAnsi literal bytes over broken ToUnicode shifts while preserving ligatures' do
    extractor = described_class.new(FakeWinAnsiOverrideReader.new)

    expect(extractor.extract_page_text(1)).to eq('He confines himself to redistribution.')
  end
end
