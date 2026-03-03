# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Kindle::MetadataParser do
  describe '.parse' do
    it 'extracts canonical metadata from MOBI and EXTH values' do
      mobi = instance_double('MobiHeader', full_name: 'Legacy Title')
      exth = instance_double(
        'Exth',
        updated_title: 'Updated Title',
        authors: ['Jane Austen'],
        publishing_date: '1818-12-20',
        language: 'en'
      )

      metadata = described_class.parse(mobi: mobi, exth: exth, fallback_title: 'Fallback')

      expect(metadata).to eq(
        title: 'Updated Title',
        authors: ['Jane Austen'],
        year: '1818',
        language: 'en'
      )
    end
  end

  describe 'delegation' do
    it 'is used by KindleMetadataExtractor and preserves author_str output' do
      pdb = instance_double(Shoko::Core::BookFormats::Kindle::PdbHeaderParser, record_data: 'record0')
      mobi = instance_double(
        Shoko::Core::BookFormats::Kindle::MobiHeaderParser,
        has_exth?: true,
        exth_offset: 0,
        encoding_name: 'UTF-8'
      )
      exth = instance_double(Shoko::Core::BookFormats::Kindle::ExthParser)
      path_ops = Class.new do
        include Shoko::Core::Ports::Outbound::PathOps

        def expand_path(path, dir = nil)
          File.expand_path(path, dir)
        end

        def join(*parts)
          File.join(*parts)
        end

        def basename(_path)
          'book_name.mobi'
        end

        def extname(path)
          File.extname(path)
        end
      end.new

      allow(Shoko::Core::BookFormats::Kindle::PdbHeaderParser).to receive(:new).and_return(pdb)
      allow(Shoko::Core::BookFormats::Kindle::MobiHeaderParser).to receive(:new).with('record0').and_return(mobi)
      allow(Shoko::Core::BookFormats::Kindle::ExthParser).to receive(:new).and_return(exth)
      allow(described_class).to receive(:parse).and_return(
        title: 'Book Name',
        authors: ['Author Name'],
        year: '2020',
        language: 'en'
      )

      metadata = Shoko::Core::BookFormats::Kindle::KindleMetadataExtractor.from_file(
        '/tmp/book_name.mobi',
        file_reader: ->(_path) { 'raw-bytes' },
        path_ops: path_ops
      )

      expect(described_class).to have_received(:parse).with(
        mobi: mobi,
        exth: exth,
        fallback_title: 'book name'
      )
      expect(metadata[:title]).to eq('Book Name')
      expect(metadata[:authors]).to eq(['Author Name'])
      expect(metadata[:author_str]).to eq('Author Name')
    end

    it 'is used by KindleImporter metadata extraction and preserves author_str' do
      importer = Shoko::Adapters::BookSources::Kindle::KindleImporter.new
      mobi = instance_double(
        Shoko::Core::BookFormats::Kindle::MobiHeaderParser,
        has_exth?: true,
        exth_offset: 0,
        encoding_name: 'UTF-8'
      )
      exth = instance_double(Shoko::Core::BookFormats::Kindle::ExthParser)
      importer.instance_variable_set(:@mobi, mobi)

      allow(Shoko::Core::BookFormats::Kindle::ExthParser).to receive(:new).and_return(exth)
      allow(described_class).to receive(:parse).and_return(
        title: 'Importer Title',
        authors: ['Importer Author'],
        year: '2019',
        language: nil
      )

      metadata = importer.send(:extract_metadata, 'record0-with-exth')

      expect(described_class).to have_received(:parse).with(
        mobi: mobi,
        exth: exth,
        fallback_title: nil
      )
      expect(metadata[:title]).to eq('Importer Title')
      expect(metadata[:authors]).to eq(['Importer Author'])
      expect(metadata[:author_str]).to eq('Importer Author')
    end
  end
end
