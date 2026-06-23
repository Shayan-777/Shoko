# frozen_string_literal: true

require 'json'
require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Pdf::PdfImporter do
  subject(:importer) { described_class.new }

  describe 'PDF extraction flow internals' do
    it 'prefers layout payload serialization when layout lines are available' do
      extractor = instance_double(Shoko::Adapters::BookSources::Pdf::PdfTextExtractor)
      allow(extractor).to receive(:extract_page_layout).with(11).and_return(
        [{ text: 'Line A', x: 72.0, italic: false, italic_ratio: 0.0 }]
      )
      allow(extractor).to receive(:extract_page_text).with(11).and_return('fallback text should not be used')

      importer.instance_variable_set(:@pages, [11])
      importer.instance_variable_set(:@extractor, extractor)

      raw = importer.send(:extract_pages_text, 0, 0)
      payload = JSON.parse(raw)

      expect(payload['format']).to eq('pdf-layout-v1')
      expect(payload['lines'].length).to eq(1)
      expect(payload['lines'][0]['text']).to eq('Line A')
      expect(payload['lines'][0]['italic']).to eq(false)
      expect(payload['lines'][0]['italic_ratio']).to eq(0.0)
    end

    it 'falls back to joined plain text when layout extraction is empty' do
      extractor = instance_double(Shoko::Adapters::BookSources::Pdf::PdfTextExtractor)
      allow(extractor).to receive(:extract_page_layout).and_return([])
      allow(extractor).to receive(:extract_page_text).with(11).and_return('Page 1')
      allow(extractor).to receive(:extract_page_text).with(22).and_return('Page 2')

      importer.instance_variable_set(:@pages, [11, 22])
      importer.instance_variable_set(:@extractor, extractor)

      raw = importer.send(:extract_pages_text, 0, 1)
      expect(raw).to eq("Page 1\n\nPage 2")
    end

    it 'continues extraction when one page fails to extract' do
      extractor = instance_double(Shoko::Adapters::BookSources::Pdf::PdfTextExtractor)
      allow(extractor).to receive(:extract_page_layout).with(11).and_raise(
        Shoko::RenderError.new('pdf_layout', 'bad page')
      )
      allow(extractor).to receive(:extract_page_text).with(11).and_raise(
        Shoko::RenderError.new('pdf_text', 'bad page')
      )
      allow(extractor).to receive(:extract_page_layout).with(22).and_return([])
      allow(extractor).to receive(:extract_page_text).with(22).and_return('Page 2')

      importer.instance_variable_set(:@pages, [11, 22])
      importer.instance_variable_set(:@extractor, extractor)

      expect(importer.send(:extract_pages_text, 0, 1)).to eq('Page 2')
    end
  end

  describe 'outline bookmarks sharing a page' do
    let(:outlines) do
      [
        { title: 'Introduction', page_idx: 0, depth: 0 },
        { title: 'Biopsychosocial Impact', page_idx: 0, depth: 0 },
        { title: 'Methods', page_idx: 1, depth: 0 },
        { title: 'Results', page_idx: 2, depth: 0 },
        { title: 'Conclusion', page_idx: 2, depth: 1 },
      ]
    end

    before do
      importer.instance_variable_set(:@pages, [10, 20, 30, 40, 50])
      allow(importer).to receive(:extract_pages_text).and_return('')
    end

    it 'collapses same-page bookmarks into disjoint chapters so no page is rendered twice' do
      chapters = importer.send(:build_outline_chapters, outlines)

      ranges = chapters.map { |chapter| [chapter.metadata[:start_page], chapter.metadata[:end_page]] }
      expect(ranges).to eq([[0, 0], [1, 1], [2, 4]])
      expect(chapters.map(&:title)).to eq(%w[Introduction Methods Results])
    end

    it 'keeps every bookmark in the TOC, each pointing at the chapter that contains its page' do
      chapters = importer.send(:build_outline_chapters, outlines)
      toc = importer.send(:build_toc_entries, outlines, chapters)

      expect(toc.map(&:title)).to include('Biopsychosocial Impact', 'Conclusion')
      expect(toc.map(&:chapter_index)).to eq([0, 0, 1, 2, 2])
    end
  end

  describe '#import metadata defaults and extraction contract' do
    let(:path) { '/tmp/no_metadata.pdf' }
    let(:reader) { instance_double(Shoko::Adapters::BookSources::Pdf::PdfReader) }
    let(:extractor) { instance_double(Shoko::Adapters::BookSources::Pdf::PdfTextExtractor) }

    before do
      allow(File).to receive(:file?).with(File.expand_path(path)).and_return(true)
      allow(File).to receive(:binread).with(File.expand_path(path)).and_return('%PDF-1.7')

      allow(Shoko::Adapters::BookSources::Pdf::PdfReader).to receive(:new).and_return(reader)
      allow(Shoko::Adapters::BookSources::Pdf::PdfTextExtractor).to receive(:new).with(reader).and_return(extractor)

      allow(reader).to receive(:page_object_numbers).and_return([11])
      allow(reader).to receive(:info_obj_num).and_return(nil)
      allow(reader).to receive(:root_obj_num).and_return(nil)
      allow(reader).to receive(:read_object_raw).with(nil).and_return(nil)

      allow(extractor).to receive(:extract_page_layout).with(11).and_return([])
      allow(extractor).to receive(:extract_page_text).with(11).and_return('Only page')
    end

    it 'uses default language when metadata is missing' do
      book = importer.import(path)

      expect(book.language).to eq('en_US')
      expect(book.metadata).to eq({})
      expect(book.chapters.length).to eq(1)
    end

    it 'calls extractor with page object numbers from reader' do
      importer.import(path)

      expect(extractor).to have_received(:extract_page_layout).with(11).at_least(:once)
      expect(extractor).to have_received(:extract_page_text).with(11).at_least(:once)
    end
  end
end
