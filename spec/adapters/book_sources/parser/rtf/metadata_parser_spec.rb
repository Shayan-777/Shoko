# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Rtf::MetadataParser do
  FakeInfo = Struct.new(:title, :author, :creatim)
  FakeRun = Struct.new(:text, :font_size, :bold)
  FakeParagraph = Struct.new(:runs, :alignment)
  FakeDoc = Struct.new(:info, :paragraphs)

  describe '.parse' do
    it 'extracts canonical metadata from info and content heuristics' do
      info = FakeInfo.new(title: '[Version 2', author: 'ignored', creatim: '2005-03-01')
      paragraphs = [
        FakeParagraph.new(
          alignment: :center,
          runs: [FakeRun.new(text: 'Pride and Prejudice', font_size: 48, bold: true)]
        ),
        FakeParagraph.new(
          alignment: :center,
          runs: [FakeRun.new(text: 'Jane Austen', font_size: 32, bold: true)]
        ),
      ]
      doc = FakeDoc.new(info: info, paragraphs: paragraphs)

      metadata = described_class.parse(doc: doc, fallback_title: 'fallback')

      expect(metadata).to eq(
        title: 'Pride and Prejudice',
        authors: ['Jane Austen'],
        year: '2005',
        language: nil
      )
    end
  end

  describe 'delegation' do
    it 'is used by RtfMetadataExtractor and preserves author_str' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'my_book.rtf')
        File.binwrite(path, '{\\rtf1\\ansi test}')

        expect(described_class).to receive(:parse).with(
          hash_including(fallback_title: 'my book')
        ).and_return(
          title: 'My Book',
          authors: ['Author Name'],
          year: '2020',
          language: nil
        )

        result = Shoko::Adapters::BookSources::Rtf::RtfMetadataExtractor.from_file(
          path,
          file_probe: File,
          file_reader: ->(target) { File.binread(target) },
          path_ops: Class.new do
            include Shoko::Application::Ports::Outbound::PathOps

            def expand_path(path, dir = nil)
              File.expand_path(path, dir)
            end

            def join(*parts)
              File.join(*parts)
            end

            def basename(target)
              File.basename(target)
            end

            def extname(target)
              File.extname(target)
            end
          end.new
        )

        expect(result[:title]).to eq('My Book')
        expect(result[:authors]).to eq(['Author Name'])
        expect(result[:author_str]).to eq('Author Name')
      end
    end

    it 'is used by RtfImporter metadata extraction and preserves author_str' do
      importer = Shoko::Adapters::BookSources::Rtf::RtfImporter.new
      importer.instance_variable_set(:@rtf_path, '/tmp/my_book.rtf')
      fake_doc = instance_double(Shoko::Adapters::BookSources::Rtf::RtfParser::DocumentModel)

      allow(described_class).to receive(:parse).and_return(
        title: 'My Book',
        authors: ['Importer Author'],
        year: '2020',
        language: nil
      )

      metadata = importer.send(:extract_metadata, fake_doc)

      expect(described_class).to have_received(:parse).with(doc: fake_doc, fallback_title: 'my book')
      expect(metadata[:title]).to eq('My Book')
      expect(metadata[:authors]).to eq(['Importer Author'])
      expect(metadata[:author_str]).to eq('Importer Author')
    end
  end
end
