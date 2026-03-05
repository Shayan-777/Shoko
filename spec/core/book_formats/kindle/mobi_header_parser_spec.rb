# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Kindle::MobiHeaderParser do
  def build_record0(compression: 2, text_length: 4096, text_records: 1, record_size: 4096,
                    encryption: 0, mobi_type: 2, encoding: 65_001, version: 6,
                    header_length: 232, exth_flags: 0x40, extra_flags: 0,
                    full_name: 'Test Book')
    # PalmDOC header (16 bytes): compression(2) + unused(2) + text_length(4) + records(2) + size(2) + encryption(2) + unused(2)
    data = [compression, 0, text_length, text_records, record_size, encryption, 0].pack('nnNnnnn')

    # MOBI header (starts at offset 16)
    mobi = 'MOBI'                                     # identifier
    mobi += [header_length].pack('N')                 # header length
    mobi += [mobi_type].pack('N')                     # mobi type
    mobi += [encoding].pack('N')                      # text encoding
    mobi += [0].pack('N')                             # unique ID
    mobi += [version].pack('N')                       # file version
    mobi += [0xFFFFFFFF].pack('N')                    # orthographic index
    mobi += [0xFFFFFFFF].pack('N')                    # inflection index
    mobi += [text_records + 1].pack('N')              # first non-book record

    # Full name offset (52) and length (56) — place name after MOBI header
    name_offset = 16 + header_length + 100  # after MOBI + EXTH space
    mobi += [name_offset].pack('N')                   # full name offset
    mobi += [full_name.bytesize].pack('N')            # full name length

    mobi += [0].pack('N')                             # language
    mobi += [0, 0].pack('NN')                         # input/output language
    mobi += [6].pack('N')                             # min MOBI version
    mobi += [text_records + 1].pack('N')              # first image record
    mobi += [0, 0, 0].pack('NNN')                     # huffdic offset/count/flags
    mobi += [0xFFFFFFFF, 0, 0, 0].pack('NNNN')       # DRM fields (offset 92-108)
    # Pad to fill up to offset 128 (112 in MOBI header)
    while mobi.bytesize < (128 - 16)
      mobi += "\x00\x00\x00\x00"
    end

    mobi += [exth_flags].pack('N')                    # EXTH flags at offset 128

    # Pad to reach exactly offset 226 in mobi (= offset 242 in record0)
    target_mobi_offset = 242 - 16 # extra_data_flags at abs offset 242
    while mobi.bytesize < target_mobi_offset
      mobi += "\x00"
    end

    mobi += [extra_flags].pack('n')                   # extra data flags (uint16 at offset 242)

    # Pad to full header length
    while mobi.bytesize < header_length
      mobi += "\x00"
    end

    # Trim to exact header length
    mobi = mobi[0, header_length]

    record0 = data + mobi

    # Add space for EXTH and name
    while record0.bytesize < name_offset
      record0 += "\x00"
    end
    record0 += full_name

    record0.b
  end

  it 'parses compression type and text metadata' do
    r0 = build_record0(compression: 2, text_length: 50_000, text_records: 13)
    mobi = described_class.new(r0)

    expect(mobi.compression_type).to eq(2)
    expect(mobi.text_length).to eq(50_000)
    expect(mobi.text_record_count).to eq(13)
    expect(mobi.palmdoc_compressed?).to be true
  end

  it 'detects EXTH header presence' do
    r0_with_exth = build_record0(exth_flags: 0x40)
    r0_without_exth = build_record0(exth_flags: 0x00)

    expect(described_class.new(r0_with_exth).has_exth?).to be true
    expect(described_class.new(r0_without_exth).has_exth?).to be false
  end

  it 'reports KF8 for version 8' do
    r0_v6 = build_record0(version: 6)
    r0_v8 = build_record0(version: 8)

    expect(described_class.new(r0_v6).kf8?).to be false
    expect(described_class.new(r0_v8).kf8?).to be true
  end

  it 'returns correct encoding name' do
    r0_utf8 = build_record0(encoding: 65_001)
    r0_cp1252 = build_record0(encoding: 1252)

    expect(described_class.new(r0_utf8).encoding_name).to eq('UTF-8')
    expect(described_class.new(r0_cp1252).encoding_name).to eq('Windows-1252')
  end

  it 'detects DRM' do
    r0_clean = build_record0(encryption: 0)
    r0_drm = build_record0(encryption: 2)

    expect(described_class.new(r0_clean).drm?).to be false
    expect(described_class.new(r0_drm).drm?).to be true
  end

  it 'extracts full book name' do
    r0 = build_record0(full_name: 'Pride & Prejudice')
    mobi = described_class.new(r0)

    expect(mobi.full_name).to eq('Pride & Prejudice')
  end

  it 'reads extra_data_flags correctly' do
    r0 = build_record0(extra_flags: 7, header_length: 232)
    mobi = described_class.new(r0)

    expect(mobi.extra_data_flags).to eq(7)
    expect(mobi.trailing_entry_count).to eq(3)
    expect(mobi.multibyte_overlap?).to be true
  end

  it 'raises on invalid MOBI magic' do
    r0 = build_record0
    r0 = r0.dup
    r0[16, 4] = 'NOPE'

    expect { described_class.new(r0) }.to raise_error(Shoko::BookParseError, /Invalid MOBI header magic/)
  end

  context 'with real files', :requires_book_fixtures do

    %w[Pride\ and\ Prejudice\ (Jane\ Austen).mobi Pride\ Prejudice\ (Jane\ Austen).azw Pride\ and\ Prejudice\ (Jane\ Austen).azw3].each do |filename|
      it "parses MOBI header from #{filename}" do
        path = book_fixture_path(filename)

        data = File.binread(path)
        pdb = Shoko::Core::BookFormats::Kindle::PdbHeaderParser.new(data)
        r0 = pdb.record_data(0)
        mobi = described_class.new(r0)

        expect(mobi.compression_type).to eq(2)
        expect(mobi.text_encoding).to eq(65_001)
        expect(mobi.text_record_count).to be > 0
        expect(mobi.encryption_type).to eq(0)
        expect(mobi.full_name).not_to be_empty
      end
    end
  end
end
