# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Kindle::PdbHeaderParser do
  def build_pdb_data(name: 'TestBook', type: 'BOOK', creator: 'MOBI', num_records: 3, record_contents: nil)
    record_contents ||= ["\x00" * 100, "\x01" * 50, "\x02" * 75]

    # PDB header (78 bytes)
    header = name.ljust(32, "\x00").b[0, 32]
    header << [0, 0].pack('nn')                           # attributes, version
    header << [0, 0, 0].pack('NNN')                       # creation, modification, backup dates
    header << [0, 0, 0].pack('NNN')                       # mod number, appinfo, sortinfo
    header << type.ljust(4, "\x00").b[0, 4]               # type
    header << creator.ljust(4, "\x00").b[0, 4]            # creator
    header << [0, 0].pack('NN')                           # uniqueidseed, nextrecordlistid
    header << [num_records].pack('n')                     # num records

    # Record offset table
    data_start = 78 + (num_records * 8) + 2 # +2 gap
    offsets = []
    current_offset = data_start
    record_contents.each do |content|
      offsets << current_offset
      current_offset += content.bytesize
    end

    offsets.each_with_index do |offset, i|
      header << [offset].pack('N')
      header << [0].pack('C')      # attributes
      header << [i].pack('N')[1, 3] # unique ID (24-bit)
    end

    # Gap bytes
    header << "\x00\x00"

    # Record data
    record_contents.each { |content| header << content.b }

    header
  end

  it 'parses PDB header name, type, and creator' do
    data = build_pdb_data(name: 'My_Book', type: 'BOOK', creator: 'MOBI')
    pdb = described_class.new(data)

    expect(pdb.name).to eq('My_Book')
    expect(pdb.type).to eq('BOOK')
    expect(pdb.creator).to eq('MOBI')
  end

  it 'parses the correct number of records' do
    data = build_pdb_data(num_records: 3)
    pdb = described_class.new(data)

    expect(pdb.num_records).to eq(3)
  end

  it 'extracts record data by index' do
    contents = ['AAAA', 'BBBB', 'CCCC']
    data = build_pdb_data(record_contents: contents)
    pdb = described_class.new(data)

    expect(pdb.record_data(0)).to eq('AAAA')
    expect(pdb.record_data(1)).to eq('BBBB')
    expect(pdb.record_data(2)).to eq('CCCC')
  end

  it 'reports correct record sizes' do
    contents = ['AB', 'CDEF', 'G']
    data = build_pdb_data(record_contents: contents)
    pdb = described_class.new(data)

    expect(pdb.record_size(0)).to eq(2)
    expect(pdb.record_size(1)).to eq(4)
    expect(pdb.record_size(2)).to eq(1)
  end

  it 'raises on out-of-range record index' do
    data = build_pdb_data(num_records: 2, record_contents: ['A', 'B'])
    pdb = described_class.new(data)

    expect { pdb.record_data(5) }.to raise_error(ArgumentError)
  end

  it 'raises on truncated file' do
    expect { described_class.new('too short') }.to raise_error(Shoko::BookParseError)
  end

  context 'with real MOBI file', :requires_book_fixtures do
    let(:mobi_path) { book_fixture_path('Persuasion (Jane Austen).mobi') }

    it 'parses the PDB header from a real MOBI file' do
      data = File.binread(mobi_path)
      pdb = described_class.new(data)

      expect(pdb.type).to eq('BOOK')
      expect(pdb.creator).to eq('MOBI')
      expect(pdb.num_records).to be > 10
      expect(pdb.name).not_to be_empty
    end
  end
end
