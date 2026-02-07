# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Kindle::KindleMetadataExtractor do
  let(:base_dir) { File.join(File.dirname(__FILE__), '../../../..') }

  {
    'Persuasion (Jane Austen).mobi' => { title: 'Persuasion', author: 'Jane Austen' },
    'Pride Prejudice (Jane Austen).azw' => { title: 'Pride & Prejudice', author: 'Jane Austen' },
    'Emma (Jane Austen).azw3' => { title: 'Emma', author: 'Jane Austen' },
  }.each do |filename, expected|
    context "with #{filename}" do
      let(:path) { File.join(base_dir, filename) }

      before { skip "#{filename} not available" unless File.exist?(path) }

      it 'extracts title' do
        meta = described_class.from_file(path)
        expect(meta[:title]).to eq(expected[:title])
      end

      it 'extracts author' do
        meta = described_class.from_file(path)
        expect(meta[:authors]).to include(expected[:author])
      end

      it 'includes author_str' do
        meta = described_class.from_file(path)
        expect(meta[:author_str]).to include(expected[:author])
      end

      it 'returns a hash with expected keys' do
        meta = described_class.from_file(path)
        expect(meta).to be_a(Hash)
        expect(meta).to have_key(:title)
        expect(meta).to have_key(:authors)
      end
    end
  end

  it 'returns empty hash for non-existent file' do
    meta = described_class.from_file('/nonexistent/file.mobi')
    expect(meta).to eq({})
  end

  it 'returns empty hash for invalid file' do
    tmpfile = Tempfile.new(['test', '.mobi'])
    tmpfile.write('not a valid mobi file')
    tmpfile.close

    meta = described_class.from_file(tmpfile.path)
    expect(meta).to eq({})
  ensure
    tmpfile&.unlink
  end
end
