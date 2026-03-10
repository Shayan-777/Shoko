# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'

RSpec.describe 'Metadata parser schema contract' do
  it 'enforces canonical parser schema for PDF metadata parser' do
    metadata = Shoko::Adapters::BookSources::Pdf::MetadataParser.parse(
      title: 'Title',
      author: 'Author',
      creation_date: 'D:20010101'
    )

    expect(metadata.keys).to eq(%i[title authors year language])
    expect(metadata[:authors]).to eq(['Author'])
  end

  it 'enforces canonical parser schema for RTF metadata parser' do
    doc = Struct.new(:info, :paragraphs, keyword_init: true).new(
      info: Struct.new(:title, :author, :creatim, keyword_init: true).new(
        title: 'RTF Title',
        author: 'RTF Author',
        creatim: '2005-01-01'
      ),
      paragraphs: []
    )

    metadata = Shoko::Adapters::BookSources::Rtf::MetadataParser.parse(doc: doc, fallback_title: 'Fallback')

    expect(metadata.keys).to eq(%i[title authors year language])
    expect(metadata[:authors]).to eq(['RTF Author'])
  end

  it 'enforces canonical parser schema for FB2 metadata parser' do
    xml = <<~XML
      <FictionBook>
        <description>
          <title-info>
            <book-title>FB2 Title</book-title>
            <author><first-name>FB2</first-name><last-name>Author</last-name></author>
            <lang>en</lang>
            <date value="1843-01-01">1843</date>
          </title-info>
        </description>
      </FictionBook>
    XML
    doc = REXML::Document.new(xml)

    metadata = Shoko::Adapters::BookSources::Fb2::MetadataParser.parse_document(doc)

    expect(metadata.keys).to eq(%i[title authors year language])
    expect(metadata[:authors]).to eq(['FB2 Author'])
  end

  it 'enforces canonical parser schema for Kindle metadata parser' do
    mobi = instance_double('MobiHeader', full_name: 'Kindle Title')
    exth = instance_double('Exth',
                           updated_title: 'Kindle Title',
                           authors: ['Kindle Author'],
                           publishing_date: '2004-01-01',
                           language: 'en')

    metadata = Shoko::Adapters::BookSources::Kindle::MetadataParser.parse(
      mobi: mobi,
      exth: exth,
      fallback_title: 'Fallback'
    )

    expect(metadata.keys).to eq(%i[title authors year language])
    expect(metadata[:authors]).to eq(['Kindle Author'])
  end
end
