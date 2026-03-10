# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'

RSpec.describe Shoko::Adapters::BookSources::Fb2::MetadataParser do
  let(:fb2_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
        <description>
          <title-info>
            <book-title>FB2 Title</book-title>
            <author>
              <first-name>Ada</first-name>
              <last-name>Lovelace</last-name>
            </author>
            <lang>en</lang>
            <date value="1843-01-01">1843</date>
            <genre>science</genre>
          </title-info>
        </description>
        <body>
          <section><title><p>Chapter 1</p></title><p>Body</p></section>
        </body>
      </FictionBook>
    XML
  end

  describe '.parse_document' do
    it 'extracts canonical metadata from FB2 title-info' do
      doc = REXML::Document.new(fb2_xml.gsub(/\s+xmlns\s*=\s*["'][^"']*["']/, ''))

      metadata = described_class.parse_document(doc)

      expect(metadata).to eq(
        title: 'FB2 Title',
        authors: ['Ada Lovelace'],
        year: '1843',
        language: 'en'
      )
    end
  end

  describe 'delegation' do
    it 'is used by Fb2MetadataExtractor and preserves extractor output shape' do
      allow(described_class).to receive(:parse_document).and_return(
        title: 'FB2 Title',
        authors: ['Ada Lovelace'],
        year: '1843',
        language: 'en'
      )

      metadata = Shoko::Adapters::BookSources::Fb2::Fb2MetadataExtractor.from_file(
        '/tmp/book.fb2',
        text_reader: ->(_path) { fb2_xml }
      )

      expect(described_class).to have_received(:parse_document).with(instance_of(REXML::Document))
      expect(metadata[:title]).to eq('FB2 Title')
      expect(metadata[:authors]).to eq(['Ada Lovelace'])
      expect(metadata[:author_str]).to eq('Ada Lovelace')
      expect(metadata[:year]).to eq('1843')
    end

    it 'is used by Fb2Importer metadata extraction' do
      importer = Shoko::Adapters::BookSources::Fb2::Fb2Importer.new
      doc = REXML::Document.new(fb2_xml.gsub(/\s+xmlns\s*=\s*["'][^"']*["']/, ''))

      allow(described_class).to receive(:parse_document).and_return(
        title: 'FB2 Title',
        authors: ['Ada Lovelace'],
        year: '1843',
        language: 'en'
      )

      metadata = importer.send(:extract_metadata, doc)

      expect(described_class).to have_received(:parse_document).with(doc)
      expect(metadata[:title]).to eq('FB2 Title')
      expect(metadata[:authors]).to eq(['Ada Lovelace'])
      expect(metadata[:year]).to eq('1843')
      expect(metadata[:language]).to eq('en')
    end
  end
end
