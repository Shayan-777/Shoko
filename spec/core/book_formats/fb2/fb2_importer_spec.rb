# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Fb2::Fb2Importer do
  def write_fb2(content)
    file = Tempfile.new(['book', '.fb2'])
    file.write(content)
    file.flush
    file
  end

  let(:fb2_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
        <description>
          <title-info>
            <book-title>Sample FB2</book-title>
            <author><first-name>Jane</first-name><last-name>Doe</last-name></author>
            <lang>en</lang>
          </title-info>
        </description>
        <body>
          <section>
            <title><p>Chapter 1</p></title>
            <p>Hello world.</p>
            <image href="#img1"/>
          </section>
        </body>
        <binary id="img1" content-type="image/png">SGVsbG8=</binary>
      </FictionBook>
    XML
  end

  it 'does not extract binary resources by default' do
    file = write_fb2(fb2_xml)
    book = described_class.new.import(file.path)

    expect(book.resources).to eq({})
  ensure
    file&.close!
  end

  it 'extracts binary resources when extract_resources is enabled' do
    file = write_fb2(fb2_xml)
    book = described_class.new(extract_resources: true).import(file.path)

    expect(book.resources.keys).to include('img1')
    expect(book.resources['img1']).to eq('Hello'.b)
  ensure
    file&.close!
  end
end
