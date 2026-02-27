# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/shoko/core/book_formats/pdf/metadata_parser'
require_relative '../../../../lib/shoko/core/book_formats/pdf/pdf_metadata_extractor'
require_relative '../../../../lib/shoko/adapters/book_sources/pdf/pdf_importer'

RSpec.describe Shoko::Core::BookFormats::Pdf::MetadataParser do
  describe '.parse' do
    it 'normalizes PDF info fields into canonical metadata keys' do
      metadata = described_class.parse(
        title: '  Example Title  ',
        author: '  Jane Austen ',
        creation_date: 'D:18111216000000'
      )

      expect(metadata).to eq(
        title: 'Example Title',
        authors: ['Jane Austen'],
        year: '1811',
        language: nil
      )
    end
  end

  describe 'delegation' do
    it 'is used by PdfMetadataExtractor and preserves extractor output shape' do
      reader = instance_double(Shoko::Core::BookFormats::Pdf::PdfReader)
      allow(Shoko::Core::BookFormats::Pdf::PdfReader).to receive(:new).and_return(reader)
      allow(reader).to receive(:info_obj_num).and_return(10)
      allow(reader).to receive(:read_object_raw).with(10).and_return('raw-info')
      allow(reader).to receive(:dict_value).with('raw-info', 'Title').and_return('Parsed Title')
      allow(reader).to receive(:dict_value).with('raw-info', 'Author').and_return('Author Name')
      allow(reader).to receive(:dict_value).with('raw-info', 'Creator').and_return(nil)
      allow(reader).to receive(:dict_value).with('raw-info', 'CreationDate').and_return('D:20010101')
      allow(reader).to receive(:dict_value).with('raw-info', 'Keywords').and_return(nil)

      allow(described_class).to receive(:parse).and_return(
        title: 'Parsed Title',
        authors: ['Author Name'],
        year: '2001',
        language: nil
      )

      result = Shoko::Core::BookFormats::Pdf::PdfMetadataExtractor.from_file(
        '/tmp/book.pdf',
        file_reader: ->(_path) { 'pdf-bytes' }
      )

      expect(described_class).to have_received(:parse).with(
        hash_including(title: 'Parsed Title', author: 'Author Name', creation_date: 'D:20010101')
      )
      expect(result[:authors]).to eq(['Author Name'])
      expect(result[:author_str]).to eq('Author Name')
      expect(result[:year]).to eq('2001')
    end

    it 'is used by PdfImporter metadata extraction and preserves author_str' do
      importer = Shoko::Adapters::BookSources::Pdf::PdfImporter.new
      reader = instance_double(Shoko::Core::BookFormats::Pdf::PdfReader)
      importer.instance_variable_set(:@reader, reader)

      allow(reader).to receive(:info_obj_num).and_return(15)
      allow(reader).to receive(:read_object_raw).with(15).and_return('raw-info')
      allow(reader).to receive(:dict_value).with('raw-info', 'Title').and_return('Importer Title')
      allow(reader).to receive(:dict_value).with('raw-info', 'Author').and_return('Importer Author')
      allow(reader).to receive(:dict_value).with('raw-info', 'CreationDate').and_return('D:19991231')

      allow(described_class).to receive(:parse).and_return(
        title: 'Importer Title',
        authors: ['Importer Author'],
        year: '1999',
        language: nil
      )

      metadata = importer.send(:extract_metadata)

      expect(described_class).to have_received(:parse).with(
        hash_including(title: 'Importer Title', author: 'Importer Author', creation_date: 'D:19991231')
      )
      expect(metadata[:authors]).to eq(['Importer Author'])
      expect(metadata[:author_str]).to eq('Importer Author')
      expect(metadata[:title]).to eq('Importer Title')
    end
  end
end
