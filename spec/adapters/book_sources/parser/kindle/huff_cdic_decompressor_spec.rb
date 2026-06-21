# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Kindle::HuffCdicDecompressor do
  # A structurally-valid HUFF record (just enough for the header/table parse to
  # succeed): 'HUFF' + 0x18, then off1/off2, padding to off1, a 256-entry cache
  # table (codelen 1, terminal), and a 64-entry base table. Used to reach the
  # CDIC-loading path in the constructor.
  def valid_huff_record
    magic = "HUFF\x00\x00\x00\x18".b
    offsets = [24, 24 + (256 * 4)].pack('N2')
    padding = ("\x00" * 8).b
    cache_table = ([0x81] * 256).pack('N256') # codelen=1, terminal flag set
    base_table = ([0] * 64).pack('N64')
    magic + offsets + padding + cache_table + base_table
  end

  describe 'malformed input is rejected as a parse error (never a raw crash)' do
    it 'rejects a HUFF record with the wrong magic' do
      expect do
        described_class.new('not a huff record!!'.b, [])
      end.to raise_error(Shoko::BookParseError, /HUFF/)
    end

    it 'rejects a HUFF record whose cache table runs past the end' do
      truncated = "HUFF\x00\x00\x00\x18".b + [9999, 99_999].pack('N2')

      expect do
        described_class.new(truncated, [])
      end.to raise_error(Shoko::BookParseError, /cache table|HUFF/)
    end

    it 'rejects a CDIC record with the wrong magic' do
      expect do
        described_class.new(valid_huff_record, ['NOTACDIC and some payload'.b])
      end.to raise_error(Shoko::BookParseError, /CDIC/)
    end
  end

  # Authoritative happy-path coverage runs against a real HUFF/CDIC book so the
  # bit-exact decode is validated end to end, not against a self-built encoder
  # that could share a bug with the decoder.
  context 'with a real HUFF/CDIC book', :requires_book_fixtures do
    let(:path) { book_fixture_path('The Invention of Hugo Cabret (Selznick Brian).azw3') }
    let(:parsers) { Shoko::Adapters::BookSources::Kindle }

    def build_from_fixture
      pdb = parsers::PdbHeaderParser.new(File.binread(path))
      mobi = parsers::MobiHeaderParser.new(pdb.record_data(0))
      huff = pdb.record_data(mobi.huff_record_offset)
      cdics = (1...mobi.huff_record_count).map { |i| pdb.record_data(mobi.huff_record_offset + i) }
      [pdb, mobi, described_class.new(huff, cdics)]
    end

    it 'decompresses the first text record into clean, well-formed markup' do
      pdb, mobi, decompressor = build_from_fixture
      stripped = parsers::PalmdocDecompressor.strip_trailing_data(pdb.record_data(1), mobi.extra_data_flags)

      output = decompressor.decompress(stripped)

      expect(output).to start_with('<?xml')
      printable = output.each_byte.count { |b| (b >= 32 && b < 127) || [9, 10, 13].include?(b) }
      expect(printable.to_f / output.bytesize).to be > 0.99
    end

    it 'decompresses every text record without error' do
      pdb, mobi, decompressor = build_from_fixture

      total = 0
      mobi.text_record_count.times do |i|
        record_index = i + 1
        break if record_index >= pdb.num_records

        stripped = parsers::PalmdocDecompressor.strip_trailing_data(pdb.record_data(record_index), mobi.extra_data_flags)
        total += decompressor.decompress(stripped).bytesize
      end

      expect(total).to be > 100_000
    end
  end
end
