# frozen_string_literal: true

require 'json'
require 'spec_helper'
require_relative '../../../../lib/shoko/adapters/storage/cache/epub/serializer/serialize'

RSpec.describe 'PDF real document regressions' do
  let(:testbooks_dir) { File.expand_path('../../../../testbooks', __dir__) }
  let(:ai_path) { File.join(testbooks_dir, 'AI-in-Education_HuffPost_Blog.pdf') }
  let(:decline_path) do
    File.join(
      testbooks_dir,
      'The Decline of the West An Abridged Edition (Oswald Spengler) (an abridged edition)).pdf'
    )
  end
  let(:losurdo_path) do
    File.join(testbooks_dir, 'class struggle A Political and Philosophical History (Domenico Losurdo).pdf')
  end

  it 'imports the AI HuffPost PDF with readable outline titles and non-empty chapter content' do
    book = Shoko::Adapters::BookSources::Pdf::PdfImporter.new.import(ai_path)
    payload = JSON.parse(book.chapters.first.raw_content)
    text = payload.fetch('lines').map { |line| line['text'] }.join(' ')

    expect(book.chapters.first.title).to eq('The hype and the panic are both selling you a story')
    expect(text).to include('AI Won’t Save or Ruin School')
    expect(text).to include('The hype and the panic are both selling you a story')
  end

  it 'extracts readable title-page and body text from the scanned Decline PDF' do
    reader = Shoko::Adapters::BookSources::Pdf::PdfReader.new(File.binread(decline_path))
    extractor = Shoko::Adapters::BookSources::Pdf::PdfTextExtractor.new(reader)
    pages = reader.page_object_numbers

    title_page = extractor.extract_page_text(pages[3])
    preface_page = extractor.extract_page_text(pages[8])

    expect(title_page).to include('OSWALD')
    expect(title_page).to include('OXFORD UNIVERSITY PRESS')
    expect(preface_page).to include('PREFACE TO THE PRESENT EDITION')
    expect(preface_page).to include('Spengler')
  end

  it 'imports the Losurdo PDF with UTF-8 metadata and serializable cache payloads' do
    book = Shoko::Adapters::BookSources::Pdf::PdfImporter.new.import(losurdo_path)

    expect(book.title).to eq('Class Struggle: A Political and Philosophical History')
    expect(book.title.encoding).to eq(Encoding::UTF_8)
    expect(book.title).to be_valid_encoding
    expect(book.authors).to eq(['Domenico Losurdo'])

    expect do
      serialized = Shoko::Adapters::Storage::EpubCache::Serializer.serialize(book, json: true)
      expect(serialized.dig(:book, :title)).to eq('Class Struggle: A Political and Philosophical History')
      expect(serialized.dig(:book, :authors_json)).to include('Domenico Losurdo')
    end.not_to raise_error
  end

  it 'extracts readable body text from the Losurdo PDF pages that previously rendered as gibberish' do
    reader = Shoko::Adapters::BookSources::Pdf::PdfReader.new(File.binread(losurdo_path))
    extractor = Shoko::Adapters::BookSources::Pdf::PdfTextExtractor.new(reader)
    pages = reader.page_object_numbers
    chapter_four_page = extractor.extract_page_text(pages[78])

    expect(chapter_four_page).to include('REDISTRIBUTION OR RECOGNITION?')
    expect(chapter_four_page).to include('Emancipatory class struggle tends to transcend')
    expect(chapter_four_page).to include('redistribution represented the dominant paradigm')
    expect(chapter_four_page).not_to include('tgfkuvtkdwvkqp')
  end
end
