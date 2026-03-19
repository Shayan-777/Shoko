# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Kindle::ExthParser do
  def build_exth(records)
    data = 'EXTH'
    # We'll calculate total length after building records
    record_data = +''
    records.each do |type, value|
      rec = [type, value.bytesize + 8].pack('NN') + value.b
      record_data << rec
    end
    total_length = 12 + record_data.bytesize
    data += [total_length, records.length].pack('NN')
    data += record_data
    data.b
  end

  it 'parses author metadata' do
    exth = described_class.new(build_exth([[100, 'Jane Austen']]))

    expect(exth.author).to eq('Jane Austen')
    expect(exth.authors).to eq(['Jane Austen'])
  end

  it 'parses multiple authors' do
    exth = described_class.new(build_exth([
                                            [100, 'Author One'],
                                            [100, 'Author Two'],
                                          ]))

    expect(exth.authors).to eq(['Author One', 'Author Two'])
    expect(exth.author).to eq('Author One')
  end

  it 'parses updated title' do
    exth = described_class.new(build_exth([[503, 'Emma: A Novel']]))

    expect(exth.updated_title).to eq('Emma: A Novel')
  end

  it 'parses publisher' do
    exth = described_class.new(build_exth([[101, 'Barnes & Noble']]))

    expect(exth.publisher).to eq('Barnes & Noble')
  end

  it 'parses publishing date' do
    exth = described_class.new(build_exth([[106, '2009-05-01']]))

    expect(exth.publishing_date).to eq('2009-05-01')
  end

  it 'parses language' do
    exth = described_class.new(build_exth([[524, 'en']]))

    expect(exth.language).to eq('en')
  end

  it 'parses description' do
    exth = described_class.new(build_exth([[103, 'A fine romance']]))

    expect(exth.description).to eq('A fine romance')
  end

  it 'parses ISBN' do
    exth = described_class.new(build_exth([[104, '978-1234567890']]))

    expect(exth.isbn).to eq('978-1234567890')
  end

  it 'parses ASIN' do
    exth = described_class.new(build_exth([[113, 'B00ABCDEFG']]))

    expect(exth.asin).to eq('B00ABCDEFG')
  end

  it 'parses subject' do
    exth = described_class.new(build_exth([[105, 'Fiction']]))

    expect(exth.subject).to eq('Fiction')
  end

  it 'returns nil for missing records' do
    exth = described_class.new(build_exth([]))

    expect(exth.author).to be_nil
    expect(exth.updated_title).to be_nil
    expect(exth.publisher).to be_nil
  end

  it 'handles invalid EXTH gracefully' do
    exth = described_class.new('NOT_EXTH')

    expect(exth.author).to be_nil
    expect(exth.records).to be_empty
  end

  it 'handles truncated data gracefully' do
    exth = described_class.new("EXTH#{"\x00" * 4}")

    expect(exth.records).to be_empty
  end

  context 'with real files', :requires_book_fixtures do
    {
      'Pride and Prejudice (Jane Austen).mobi' => 'Jane Austen',
      'Pride Prejudice (Jane Austen).azw' => 'Jane Austen',
      'Pride and Prejudice (Jane Austen).azw3' => 'Jane Austen',
    }.each do |filename, expected_author|
      it "extracts author from #{filename}" do
        path = book_fixture_path(filename)

        data = File.binread(path)
        pdb = Shoko::Adapters::BookSources::Kindle::PdbHeaderParser.new(data)
        r0 = pdb.record_data(0)
        mobi = Shoko::Adapters::BookSources::Kindle::MobiHeaderParser.new(r0)
        expect(mobi.exth?).to be(true)

        exth_data = r0.byteslice(mobi.exth_offset..)
        exth = described_class.new(exth_data, encoding_name: mobi.encoding_name)

        expect(exth.author).to eq(expected_author)
      end
    end
  end
end
