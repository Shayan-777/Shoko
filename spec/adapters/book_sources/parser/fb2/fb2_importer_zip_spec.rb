# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Fb2::Fb2Importer do
  it 'imports .fb2.zip files with nested FB2 entries' do
    fb2_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
        <description>
          <title-info>
            <book-title>Zipped FB2</book-title>
            <author><first-name>Jane</first-name><last-name>Doe</last-name></author>
            <lang>en</lang>
          </title-info>
        </description>
        <body>
          <section>
            <title><p>Chapter 1</p></title>
            <p>Hello zipped world.</p>
          </section>
        </body>
      </FictionBook>
    XML

    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, 'book.fb2.zip')
      SpecZipBuilderHelper.write_stored_zip(
        zip_path,
        {
          'nested/path/book.fb2' => fb2_xml,
          'nested/path/readme.txt' => 'ignored',
        }
      )

      book = described_class.new.import(zip_path)

      expect(book.title).to eq('Zipped FB2')
      expect(book.authors).to eq(['Jane Doe'])
      expect(book.chapters).not_to be_empty
    end
  end
end
