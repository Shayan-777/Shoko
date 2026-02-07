# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Pdf::PdfTextExtractor do
  class FakePdfReader
    PAGE_RAW = '1 0 obj << /Resources 30 0 R /Contents 20 0 R >> endobj'
    RESOURCES_RAW = '30 0 obj << /Font << /F1 10 0 R /F2 11 0 R >> >> endobj'
    FONT_REGULAR_RAW = '10 0 obj << /BaseFont /Times-Roman >> endobj'
    FONT_ITALIC_RAW = '11 0 obj << /BaseFont /Times-Italic >> endobj'
    STREAM = "BT /F1 12 Tf 72 700 Td (Body line.) Tj /F2 12 Tf 220 -20 Td (Epigraph line.) Tj T* (PAUL ROBESON) Tj ET".b

    def read_object_raw(obj_num)
      case obj_num
      when 1 then PAGE_RAW
      when 30 then RESOURCES_RAW
      when 10 then FONT_REGULAR_RAW
      when 11 then FONT_ITALIC_RAW
      end
    end

    def dict_value(dict_text, key)
      case key
      when 'Resources'
        return '30 0 R' if dict_text == PAGE_RAW
      when 'Contents'
        return '20 0 R' if dict_text == PAGE_RAW
      when 'BaseFont'
        return 'Times-Roman' if dict_text == FONT_REGULAR_RAW
        return 'Times-Italic' if dict_text == FONT_ITALIC_RAW
      when 'ToUnicode', 'FontDescriptor'
        return nil
      end
      nil
    end

    def resolve_ref(ref_string)
      match = ref_string.to_s.match(/(\d+)\s+\d+\s+R/)
      match ? match[1].to_i : nil
    end

    def read_stream(obj_num)
      obj_num == 20 ? STREAM : nil
    end
  end

  class FakeMixedItalicReader
    PAGE_RAW = '1 0 obj << /Resources 30 0 R /Contents 20 0 R >> endobj'
    RESOURCES_RAW = '30 0 obj << /Font << /F1 10 0 R /F2 11 0 R >> >> endobj'
    FONT_REGULAR_RAW = '10 0 obj << /BaseFont /Times-Roman >> endobj'
    FONT_ITALIC_RAW = '11 0 obj << /BaseFont /Times-Italic >> endobj'
    STREAM = "BT /F1 12 Tf 72 700 Td (I studied law and read ) Tj /F2 12 Tf (Criminal Evidence) Tj ET".b

    def read_object_raw(obj_num)
      case obj_num
      when 1 then PAGE_RAW
      when 30 then RESOURCES_RAW
      when 10 then FONT_REGULAR_RAW
      when 11 then FONT_ITALIC_RAW
      end
    end

    def dict_value(dict_text, key)
      case key
      when 'Resources'
        return '30 0 R' if dict_text == PAGE_RAW
      when 'Contents'
        return '20 0 R' if dict_text == PAGE_RAW
      when 'BaseFont'
        return 'Times-Roman' if dict_text == FONT_REGULAR_RAW
        return 'Times-Italic' if dict_text == FONT_ITALIC_RAW
      when 'ToUnicode', 'FontDescriptor'
        return nil
      end
      nil
    end

    def resolve_ref(ref_string)
      match = ref_string.to_s.match(/(\d+)\s+\d+\s+R/)
      match ? match[1].to_i : nil
    end

    def read_stream(obj_num)
      obj_num == 20 ? STREAM : nil
    end
  end

  it 'extracts line layout with x positions and italic font hints' do
    extractor = described_class.new(FakePdfReader.new)
    lines = extractor.extract_page_layout(1)

    expect(lines.length).to eq(3)
    expect(lines[0][:text]).to eq('Body line.')
    expect(lines[0][:x]).to eq(72.0)
    expect(lines[0][:italic]).to be(false)

    expect(lines[1][:text]).to eq('Epigraph line.')
    expect(lines[1][:x]).to eq(220.0)
    expect(lines[1][:italic]).to be(true)

    expect(lines[2][:text]).to eq('PAUL ROBESON')
    expect(lines[2][:x]).to eq(220.0)
    expect(lines[2][:italic]).to be(true)
    expect(lines[2][:italic_ratio]).to be >= 0.99
  end

  it 'tracks italic ratio so mixed inline italics do not force a full italic line' do
    extractor = described_class.new(FakeMixedItalicReader.new)
    lines = extractor.extract_page_layout(1)

    expect(lines.length).to eq(1)
    expect(lines[0][:text]).to include('Criminal Evidence')
    expect(lines[0][:italic_ratio]).to be > 0.20
    expect(lines[0][:italic_ratio]).to be < 0.65
    expect(lines[0][:italic]).to be(false)
  end
end
