# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Kindle::KindleMetadataExtractor do
  let(:file_reader) { ->(path) { File.binread(path) } }
  let(:path_ops) do
    Class.new do
      include Shoko::Core::Ports::Outbound::PathOps

      def expand_path(path, dir = nil)
        File.expand_path(path, dir)
      end

      def join(*parts)
        File.join(*parts)
      end

      def basename(path)
        File.basename(path)
      end

      def extname(path)
        File.extname(path)
      end
    end.new
  end

  def extract(path)
    described_class.from_file(path, file_reader: file_reader, path_ops: path_ops)
  end

  {
    'Pride and Prejudice (Jane Austen).mobi' => { title: 'Pride and Prejudice', author: 'Jane Austen' },
    'Pride Prejudice (Jane Austen).azw' => { title: 'Pride & Prejudice', author: 'Jane Austen' },
    'Pride and Prejudice (Jane Austen).azw3' => { title: 'Pride and Prejudice', author: 'Jane Austen' },
  }.each do |filename, expected|
    context "with #{filename}", :requires_book_fixtures do
      let(:path) { book_fixture_path(filename) }

      it 'extracts title' do
        meta = extract(path)
        expect(meta[:title]).to eq(expected[:title])
      end

      it 'extracts author' do
        meta = extract(path)
        expect(meta[:authors]).to include(expected[:author])
      end

      it 'includes author_str' do
        meta = extract(path)
        expect(meta[:author_str]).to include(expected[:author])
      end

      it 'returns a hash with expected keys' do
        meta = extract(path)
        expect(meta).to be_a(Hash)
        expect(meta).to have_key(:title)
        expect(meta).to have_key(:authors)
      end
    end
  end

  it 'raises malformed metadata error for non-existent file' do
    expect { extract('/nonexistent/file.mobi') }
      .to raise_error(Shoko::MalformedMetadataInputError, /Kindle metadata extraction failed/)
  end

  it 'raises malformed metadata error for invalid file' do
    tmpfile = Tempfile.new(['test', '.mobi'])
    tmpfile.write('not a valid mobi file')
    tmpfile.close

    expect { extract(tmpfile.path) }
      .to raise_error(Shoko::MalformedMetadataInputError, /Kindle metadata extraction failed/)
  ensure
    tmpfile&.unlink
  end
end
