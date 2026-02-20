# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Kindle::KindleImporter do
  describe '#import' do
    context 'with MOBI file (Persuasion)', :requires_book_fixtures do
      let(:path) { book_fixture_path('Persuasion (Jane Austen).mobi') }

      it 'returns a BookData struct' do
        book = described_class.new.import(path)
        expect(book).to be_a(Shoko::Core::Models::BookData)
      end

      it 'extracts the correct title' do
        book = described_class.new.import(path)
        expect(book.title).to eq('Persuasion')
      end

      it 'extracts the author' do
        book = described_class.new.import(path)
        expect(book.authors).to include('Jane Austen')
      end

      it 'produces multiple chapters' do
        book = described_class.new.import(path)
        expect(book.chapters.length).to be > 10
      end

      it 'sets format_data to :mobi' do
        book = described_class.new.import(path)
        expect(book.format_data[:format]).to eq(:mobi)
      end

      it 'produces TOC entries matching chapters' do
        book = described_class.new.import(path)
        expect(book.toc_entries.length).to eq(book.chapters.length)
      end

      it 'chapters have raw_content for lazy parsing' do
        book = described_class.new.import(path)
        content_chapter = book.chapters.find { |ch| ch.raw_content.to_s.length > 500 }
        expect(content_chapter).not_to be_nil
        expect(content_chapter.raw_content).to be_a(String)
      end

      it 'content can be parsed into blocks' do
        book = described_class.new.import(path)
        chapter = book.chapters.find { |ch| ch.raw_content.to_s.length > 1000 }
        parser = Shoko::Core::BookFormats::Kindle::KindleContentParser.new(chapter.raw_content)
        blocks = parser.parse

        expect(blocks).to be_a(Array)
        expect(blocks).not_to be_empty
        expect(blocks.first).to be_a(Shoko::Core::Models::ContentBlock)
      end
    end

    context 'with AZW file (Pride & Prejudice)', :requires_book_fixtures do
      let(:path) { book_fixture_path('Pride Prejudice (Jane Austen).azw') }

      it 'extracts the correct title' do
        book = described_class.new.import(path)
        expect(book.title).to eq('Pride & Prejudice')
      end

      it 'extracts the author' do
        book = described_class.new.import(path)
        expect(book.authors).to include('Jane Austen')
      end

      it 'produces chapters with meaningful titles' do
        book = described_class.new.import(path)
        chapter_titles = book.chapters.map(&:title)
        # Pride & Prejudice should have chapters numbered 1-61
        expect(chapter_titles).to include('Chapter 1')
        expect(chapter_titles).to include('Chapter 2')
      end

      it 'sets format_data to :azw' do
        book = described_class.new.import(path)
        expect(book.format_data[:format]).to eq(:azw)
      end

      it 'has more than 60 chapters' do
        book = described_class.new.import(path)
        expect(book.chapters.length).to be >= 60
      end
    end

    context 'with AZW3/KF8 file (Emma)', :requires_book_fixtures do
      let(:path) { book_fixture_path('Emma (Jane Austen).azw3') }

      it 'extracts the correct title' do
        book = described_class.new.import(path)
        expect(book.title).to eq('Emma')
      end

      it 'extracts the author' do
        book = described_class.new.import(path)
        expect(book.authors).to include('Jane Austen')
      end

      it 'produces chapters' do
        book = described_class.new.import(path)
        expect(book.chapters.length).to be > 30
      end

      it 'sets format_data to :azw3' do
        book = described_class.new.import(path)
        expect(book.format_data[:format]).to eq(:azw3)
      end

      it 'content can be parsed from XHTML' do
        book = described_class.new.import(path)
        chapter = book.chapters.find { |ch| ch.raw_content.to_s.length > 5000 }
        expect(chapter).not_to be_nil

        parser = Shoko::Core::BookFormats::Kindle::KindleContentParser.new(chapter.raw_content)
        blocks = parser.parse

        expect(blocks).not_to be_empty
      end
    end

    context 'error handling' do
      it 'raises FileNotFoundError for missing file' do
        expect {
          described_class.new.import('/nonexistent/book.mobi')
        }.to raise_error(Shoko::FileNotFoundError)
      end

      it 'raises BookParseError for invalid file content' do
        tmpfile = Tempfile.new(['invalid', '.mobi'])
        tmpfile.write('this is not a valid mobi file at all')
        tmpfile.close

        expect {
          described_class.new.import(tmpfile.path)
        }.to raise_error(Shoko::BookParseError)
      ensure
        tmpfile&.unlink
      end
    end

    context 'FormatRegistry integration' do
      it 'is registered for .mobi' do
        cls = Shoko::Core::BookFormats::FormatRegistry.importer_for('test.mobi')
        expect(cls).to eq(described_class)
      end

      it 'is registered for .azw' do
        cls = Shoko::Core::BookFormats::FormatRegistry.importer_for('test.azw')
        expect(cls).to eq(described_class)
      end

      it 'is registered for .azw3' do
        cls = Shoko::Core::BookFormats::FormatRegistry.importer_for('test.azw3')
        expect(cls).to eq(described_class)
      end

      it 'reports all three extensions as supported' do
        expect(Shoko::Core::BookFormats::FormatRegistry.supported_extension?('book.mobi')).to be true
        expect(Shoko::Core::BookFormats::FormatRegistry.supported_extension?('book.azw')).to be true
        expect(Shoko::Core::BookFormats::FormatRegistry.supported_extension?('book.azw3')).to be true
      end
    end
  end

  describe 'fallback chapter splitting' do
    it 'splits on closing paragraph tags case-insensitively' do
      importer = described_class.new
      importer.instance_variable_set(:@kindle_path, '/tmp/test.azw3')
      html = "<P>#{'A' * 15_000}</P><P>#{'B' * 15_000}</P><P>#{'C' * 15_000}</P>"

      chapters = importer.send(:split_by_size, html)

      expect(chapters.length).to be > 1
      expect(chapters.first.raw_content).to end_with('</P>')
    end
  end
end
