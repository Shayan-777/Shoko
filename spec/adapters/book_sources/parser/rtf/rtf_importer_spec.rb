# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Rtf::RtfImporter do
  describe '#import' do
    context 'with Pride and Prejudice RTF', :requires_book_fixtures do
      let(:path) { book_fixture_path('Pride And Prejudice (Austen Jane).rtf') }

      it 'returns a BookData struct' do
        book = described_class.new.import(path)
        expect(book).to be_a(Shoko::Core::Models::BookData)
      end

      it 'extracts a meaningful title' do
        book = described_class.new.import(path)
        expect(book.title).to match(/Pride.*Prejudice/i)
      end

      it 'extracts the author' do
        book = described_class.new.import(path)
        expect(book.authors).to include('Jane Austen')
      end

      it 'produces multiple chapters' do
        book = described_class.new.import(path)
        # Pride and Prejudice has 61 chapters across 3 volumes
        expect(book.chapters.length).to be > 50
      end

      it 'sets format_data to :rtf' do
        book = described_class.new.import(path)
        expect(book.format_data[:format]).to eq(:rtf)
      end

      it 'produces TOC entries matching chapters' do
        book = described_class.new.import(path)
        expect(book.toc_entries.length).to eq(book.chapters.length)
      end

      it 'chapters have raw_content for lazy parsing' do
        book = described_class.new.import(path)
        content_chapter = book.chapters.find { |ch| ch.raw_content.to_s.length > 100 }
        expect(content_chapter).not_to be_nil
        expect(content_chapter.raw_content).to include('<')
      end

      it 'content can be parsed into blocks' do
        book = described_class.new.import(path)
        chapter = book.chapters.find { |ch| ch.raw_content.to_s.length > 500 }
        parser = Shoko::Adapters::BookSources::Rtf::RtfContentParser.new(chapter.raw_content)
        blocks = parser.parse

        expect(blocks).to be_a(Array)
        expect(blocks).not_to be_empty
        expect(blocks.first).to be_a(Shoko::Core::Models::ContentBlock)
      end

      it 'preserves italic formatting from source' do
        book = described_class.new.import(path)
        chapter = book.chapters.find { |ch| ch.raw_content.to_s.include?('<i>') }
        expect(chapter).not_to be_nil, 'Expected at least one chapter with italic text'
      end

      it 'preserves emdash characters' do
        book = described_class.new.import(path)
        all_content = book.chapters.map(&:raw_content).join
        expect(all_content).to include("\u2014")
      end

      it 'chapter titles include CHAPTER headings' do
        book = described_class.new.import(path)
        chapter_titles = book.chapters.map(&:title)
        chapter_matches = chapter_titles.grep(/CHAPTER\s+[IVXLCDM]+/)
        expect(chapter_matches.length).to be >= 50
      end

      it 'has volume headings at higher TOC level' do
        book = described_class.new.import(path)
        volume_entries = book.toc_entries.select { |e| e.title.include?('VOLUME') }
        expect(volume_entries.length).to eq(3)
        volume_entries.each { |e| expect(e.level).to eq(0) }
      end
    end

    context 'error handling' do
      it 'raises FileNotFoundError for missing file' do
        expect do
          described_class.new.import('/nonexistent/book.rtf')
        end.to raise_error(Shoko::FileNotFoundError)
      end

      it 'raises BookParseError for invalid file content' do
        tmpfile = Tempfile.new(['invalid', '.rtf'])
        tmpfile.write('this is not valid rtf content')
        tmpfile.close

        expect do
          described_class.new.import(tmpfile.path)
        end.to raise_error(Shoko::BookParseError)
      ensure
        tmpfile&.unlink
      end
    end

    context 'FormatRegistry integration' do
      it 'is registered for .rtf' do
        cls = Shoko::Adapters::BookSources::FormatRegistry.importer_for('test.rtf')
        expect(cls).to eq(described_class)
      end

      it 'reports .rtf as supported' do
        expect(Shoko::Adapters::BookSources::FormatRegistry.supported_extension?('book.rtf')).to be true
      end
    end
  end
end
