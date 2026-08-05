# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require_relative '../../../../../lib/shoko/adapters/book_sources/pdf/parser/pdf_reader'

RSpec.describe Shoko::Adapters::BookSources::Pdf::PdfReader do
  def build_reader(data, xref, compressed = {})
    reader = described_class.allocate
    reader.instance_variable_set(:@data, data.b)
    reader.instance_variable_set(:@xref, xref)
    reader.instance_variable_set(:@compressed, compressed)
    reader.instance_variable_set(:@trailer, {})
    reader.instance_variable_set(:@object_cache, {})
    reader.instance_variable_set(:@objstm_cache, {})
    reader
  end

  it 'reads raw streams by declared Length without trimming valid trailing newlines' do
    payload = "line one\n"
    object = "10 0 obj\n<</Length #{payload.bytesize}>>\nstream\n"
    object << payload
    object << "\nendstream\nendobj\n"
    reader = build_reader(object, { 10 => 0 })

    result = reader.read_stream(10)

    expect(result).to eq(payload)
  end

  it 'resolves indirect Length references when reading stream bytes' do
    payload = 'hello-world'

    stream_object = +"10 0 obj\n<</Length 11 0 R>>\nstream\n"
    stream_object << payload
    stream_object << "\nendstream\nendobj\n"
    length_offset = stream_object.bytesize
    length_object = "11 0 obj\n#{payload.bytesize}\nendobj\n"
    data = stream_object + length_object

    reader = build_reader(data, { 10 => 0, 11 => length_offset })
    result = reader.read_stream(10)

    expect(result).to eq(payload)
  end

  it 'translates a corrupt FlateDecode stream into a Shoko book-parse error, not a raw Zlib error' do
    garbage = "\xDE\xAD\xBE\xEF\x00\x01\x02\x03".b
    object = "10 0 obj\n<</Length #{garbage.bytesize} /Filter /FlateDecode>>\nstream\n"
    object << garbage
    object << "\nendstream\nendobj\n"
    reader = build_reader(object, { 10 => 0 })

    expect { reader.read_stream(10) }.to raise_error(Shoko::BookParseError, /corrupt PDF stream/)
  end

  it 'still decodes a raw-deflate stream that lacks the zlib header (retry path)' do
    payload = 'recoverable text'
    raw_deflate = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    compressed = raw_deflate.deflate(payload, Zlib::FINISH)
    raw_deflate.close

    object = "10 0 obj\n<</Length #{compressed.bytesize} /Filter /FlateDecode>>\nstream\n"
    object << compressed
    object << "\nendstream\nendobj\n"
    reader = build_reader(object, { 10 => 0 })

    expect(reader.read_stream(10)).to eq(payload)
  end

  it 'parses traditional xref sections and trailer dictionaries' do
    data = +"xref\n"
    data << "0 3\n"
    data << "0000000000 65535 f \n"
    data << "0000000010 00000 n \n"
    data << "0000000020 00000 n \n"
    data << "trailer\n"
    data << "<< /Size 3 /Root 1 0 R /Info 2 0 R >>\n"

    reader = build_reader(data, {})

    reader.send(:parse_traditional_xref, 0)
    prev = reader.send(:parse_trailer_dict_at, 0)

    expect(reader.xref[1]).to eq(10)
    expect(reader.xref[2]).to eq(20)
    expect(reader.trailer['Root']).to eq('1 0 R')
    expect(reader.trailer['Info']).to eq('2 0 R')
    expect(prev).to be_nil
  end

  it 'handles traditional xref subsections with missing rows without raising' do
    data = +"xref\n"
    data << "0 3\n"
    data << "0000000000 65535 f \n"
    data << "0000000010 00000 n \n"
    data << "trailer\n"
    data << "<< /Size 3 /Root 1 0 R >>\n"

    reader = build_reader(data, {})

    expect { reader.send(:parse_traditional_xref, 0) }.not_to raise_error
    prev = reader.send(:parse_trailer_dict_at, 0)

    expect(reader.xref[1]).to eq(10)
    expect(reader.xref[2]).to be_nil
    expect(reader.trailer['Root']).to eq('1 0 R')
    expect(prev).to be_nil
  end

  it 'rejects an oversized xref subsection before iterating its declared rows' do
    data = "xref\n0 3\n0000000000 65535 f \n".b
    reader = build_reader(data, {})
    budget = Shoko::Adapters::BookSources::ImportBudget.new(path: 'hostile.pdf', max_structural_units: 2)
    reader.instance_variable_set(:@import_budget, budget)

    expect { reader.send(:parse_traditional_xref, 0) }
      .to raise_error(Shoko::BookParseError, /PDF xref table exceeds 2 units/)
  end

  it 'parses xref stream entries into object offsets' do
    reader = build_reader(''.b, {})

    # widths: [1, 4, 2], indices: [1, 2] (objects 1 and 2)
    entry_one = [1].pack('C') + [100].pack('N') + [0].pack('n')
    entry_two = [1].pack('C') + [200].pack('N') + [0].pack('n')
    stream_data = (entry_one + entry_two).b

    reader.send(:parse_xref_stream_entries, stream_data, [1, 4, 2], [1, 2])

    expect(reader.xref[1]).to eq(100)
    expect(reader.xref[2]).to eq(200)
  end

  it 'parses xref stream entries when type/gen widths are zero' do
    reader = build_reader(''.b, {})
    stream_data = [321].pack('N')

    reader.send(:parse_xref_stream_entries, stream_data, [0, 4, 0], [5, 1])

    expect(reader.xref[5]).to eq(321)
  end

  it 'parses xref stream type-2 entries as compressed-object references' do
    reader = build_reader(''.b, {})

    # widths [1,1,1]: type=2 (compressed), field2=object-stream num, field3=index
    stream_data = ([2].pack('C') + [7].pack('C') + [3].pack('C')).b
    compressed = {}
    reader.instance_variable_set(:@compressed, compressed)

    reader.send(:parse_xref_stream_entries, stream_data, [1, 1, 1], [42, 1])

    expect(compressed[42]).to eq([7, 3])
    expect(reader.xref).not_to have_key(42)
  end

  it 'reads an object stored inside a compressed object stream (ObjStm)' do
    member0 = '<< /Type /Pages /Count 0 >>'
    member1 = '12345'
    header = "10 0 11 #{member0.bytesize} "
    first = header.bytesize
    body = header + member0 + member1
    compressed = Zlib::Deflate.deflate(body)

    objstm = +"5 0 obj\n"
    objstm << "<< /Type /ObjStm /N 2 /First #{first} /Length #{compressed.bytesize} /Filter /FlateDecode >>\n"
    objstm << "stream\n" << compressed << "\nendstream\nendobj\n"

    reader = build_reader(objstm, { 5 => 0 }, { 10 => [5, 0], 11 => [5, 1] })

    expect(reader.read_object_raw(10)).to eq(member0)
    expect(reader.read_object_raw(11)).to eq(member1)
  end

  it 'terminates page collection when the page tree cycles back on itself' do
    # /Pages 8 lists kid 9, whose Kids points back to 8 — a malformed cycle.
    node8 = "8 0 obj\n<< /Type /Pages /Kids [9 0 R] /Count 1 >>\nendobj\n"
    off9 = node8.bytesize
    node9 = "9 0 obj\n<< /Type /Pages /Kids [8 0 R] /Count 1 >>\nendobj\n"
    reader = build_reader(node8 + node9, { 8 => 0, 9 => off9 })

    pages = Timeout.timeout(5) { reader.send(:collect_pages, 8, {}) }

    expect(pages).to eq([])
  end

  it 'collects a single page reference from an inline Kids array' do
    node8 = "8 0 obj\n<< /Type /Pages /Kids [9 0 R] /Count 1 >>\nendobj\n"
    off9 = node8.bytesize
    node9 = "9 0 obj\n<< /Type /Page >>\nendobj\n"
    reader = build_reader(node8 + node9, { 8 => 0, 9 => off9 })

    expect(reader.send(:collect_pages, 8, {})).to eq([9])
  end

  it 'rejects page trees deeper than the import nesting budget' do
    node8 = "8 0 obj\n<< /Type /Pages /Kids [9 0 R] /Count 1 >>\nendobj\n"
    off9 = node8.bytesize
    node9 = "9 0 obj\n<< /Type /Pages /Kids [10 0 R] /Count 1 >>\nendobj\n"
    off10 = off9 + node9.bytesize
    node10 = "10 0 obj\n<< /Type /Page >>\nendobj\n"
    reader = build_reader(node8 + node9 + node10, { 8 => 0, 9 => off9, 10 => off10 })
    budget = Shoko::Adapters::BookSources::ImportBudget.new(path: 'nested.pdf', max_nesting: 2)
    reader.instance_variable_set(:@import_budget, budget)

    expect { reader.send(:collect_pages, 8, {}) }
      .to raise_error(Shoko::BookParseError, /PDF page tree nesting exceeds 2/)
  end

  it 'falls back to endstream scanning when referenced Length object is invalid' do
    payload = 'body'
    stream_object = +"10 0 obj\n<</Length 11 0 R>>\nstream\n"
    stream_object << payload
    stream_object << "\nendstream\nendobj\n"
    length_offset = stream_object.bytesize
    invalid_length = "11 0 obj\n(not-an-integer)\nendobj\n"
    data = stream_object + invalid_length

    reader = build_reader(data, { 10 => 0, 11 => length_offset })

    expect(reader.read_stream(10)).to eq("#{payload}\n")
  end
end
