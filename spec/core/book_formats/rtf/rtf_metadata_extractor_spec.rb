# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Rtf::RtfMetadataExtractor do
  let(:base_dir) { File.join(File.dirname(__FILE__), '../../../..') }
  let(:file_probe) do
    Class.new do
      def file?(path)
        File.file?(path)
      end
    end.new
  end
  let(:file_reader) { ->(path) { File.binread(path) } }
  let(:path_ops) do
    Class.new do
      def basename(path)
        File.basename(path)
      end
    end.new
  end

  def extract(path)
    described_class.from_file(path, file_probe: file_probe, file_reader: file_reader, path_ops: path_ops)
  end

  describe '.from_file' do
    context 'with Pride and Prejudice RTF' do
      let(:path) { File.join(base_dir, 'Pride And Prejudice (Austen Jane).rtf') }

      before { skip 'RTF file not available' unless File.exist?(path) }

      it 'returns a metadata hash' do
        meta = extract(path)
        expect(meta).to be_a(Hash)
        expect(meta).to have_key(:title)
        expect(meta).to have_key(:authors)
      end

      it 'extracts the title from content (not \\info)' do
        meta = extract(path)
        # \info title is "[Version 2" which is invalid, so content fallback
        # should find "Pride and Prejudice" from large centered text
        expect(meta[:title]).to match(/Pride.*Prejudice/i)
      end

      it 'extracts the author from content' do
        meta = extract(path)
        expect(meta[:authors]).to include('Jane Austen')
      end

      it 'includes author_str' do
        meta = extract(path)
        expect(meta[:author_str]).to include('Jane Austen')
      end

      it 'extracts year from creation date' do
        meta = extract(path)
        expect(meta[:year]).to eq('2005')
      end
    end

    it 'returns empty hash for non-existent file' do
      meta = extract('/nonexistent/file.rtf')
      expect(meta).to eq({})
    end

    it 'returns empty hash for invalid file' do
      tmpfile = Tempfile.new(['test', '.rtf'])
      tmpfile.write('not a valid rtf file')
      tmpfile.close

      meta = extract(tmpfile.path)
      expect(meta).to be_a(Hash)
      # Should still extract something (at least from filename fallback)
      expect(meta[:title]).not_to be_nil
    ensure
      tmpfile&.unlink
    end
  end
end
