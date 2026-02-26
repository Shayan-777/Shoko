# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::MetadataReaderAdapter do
  it 'extracts metadata from .fb2.zip through format registry dispatch' do
    fb2_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
        <description>
          <title-info>
            <book-title>Metadata FB2</book-title>
            <author><first-name>Ada</first-name><last-name>Lovelace</last-name></author>
            <lang>en</lang>
            <date value="1843-01-01">1843</date>
          </title-info>
        </description>
        <body>
          <section><title><p>Chapter</p></title><p>Body</p></section>
        </body>
      </FictionBook>
    XML

    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, 'metadata.fb2.zip')
      SpecZipBuilderHelper.write_stored_zip(
        zip_path,
        {
          'books/metadata.fb2' => fb2_xml
        }
      )

      adapter = described_class.new
      metadata = adapter.extract_metadata(zip_path)

      expect(metadata[:title]).to eq('Metadata FB2')
      expect(metadata[:authors]).to eq(['Ada Lovelace'])
      expect(metadata[:year]).to eq('1843')
    end
  end
end
