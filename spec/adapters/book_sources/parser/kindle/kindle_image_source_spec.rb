# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Shoko::Adapters::BookSources::Kindle::KindleImageSource do
  # A fake PDB whose records are: header, text, JPEG, text, PNG. The source must
  # ignore non-image records and map imageN to the Nth image record in order.
  let(:records) do
    [
      'MOBI-header-record',
      '<html>chapter text</html>',
      "\xFF\xD8\xFF\xE0jpeg-payload-one".b,
      'another text record',
      "\x89PNG\r\n\x1a\npng-payload-two".b,
    ]
  end

  let(:fake_pdb_class) do
    recs = records
    Class.new do
      define_method(:initialize) { |_data| @recs = recs }
      define_method(:num_records) { @recs.length }
      define_method(:record_data) { |index| @recs[index] }
    end
  end

  subject(:source) { described_class.new(pdb_parser: fake_pdb_class) }

  around do |example|
    Tempfile.create(['book', '.azw3']) do |file|
      file.write('ignored-by-fake-parser')
      file.flush
      @path = file.path
      example.run
    end
  end

  it 'maps imageNNNN.jpg to the Nth embedded image record, in order' do
    expect(source.fetch(@path, 'image0001.jpg')).to eq(records[2])
    expect(source.fetch(@path, 'image0002.jpg')).to eq(records[4])
  end

  it 'returns nil for an out-of-range image index' do
    expect(source.fetch(@path, 'image0003.jpg')).to be_nil
  end

  it 'returns nil for a non-image entry name' do
    expect(source.fetch(@path, 'stylesheet.css')).to be_nil
  end

  it 'returns nil when the file does not exist' do
    expect(source.fetch('/no/such/book.azw3', 'image0001.jpg')).to be_nil
  end

  context 'with a real HUFF/CDIC book', :requires_book_fixtures do
    let(:path) { book_fixture_path('The Invention of Hugo Cabret (Selznick Brian).azw3') }

    it 'extracts a real embedded image as valid JPEG bytes' do
      bytes = described_class.new.fetch(path, 'image0001.jpg')

      expect(bytes).not_to be_nil
      expect(bytes.b).to start_with("\xFF\xD8\xFF".b)
      expect(bytes.bytesize).to be > 1000
    end
  end
end
