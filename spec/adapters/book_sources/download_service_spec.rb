# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Shoko::Adapters::BookSources::DownloadService do
  let(:client) { instance_double('GutendexClient') }
  let(:downloads_root) { Dir.mktmpdir }
  let(:service) do
    described_class.new(
      gutendex_client: client,
      downloads_root: downloads_root
    )
  end

  after do
    FileUtils.rm_rf(downloads_root) if downloads_root && File.directory?(downloads_root)
  end

  describe '#search' do
    it 'normalizes client payload into book list hashes' do
      payload = {
        'count' => 1,
        'next' => nil,
        'previous' => nil,
        'results' => [
          {
            'id' => 11,
            'title' => 'Alice',
            'authors' => [{ 'name' => 'Lewis Carroll' }],
            'languages' => %w[en],
            'download_count' => 42,
            'formats' => { 'application/epub+zip' => 'https://example.org/alice.epub' },
          },
        ],
      }
      allow(client).to receive(:search).with(query: 'alice', page_url: nil).and_return(payload)

      result = service.search(query: 'alice')

      expect(result[:count]).to eq(1)
      expect(result[:books]).to eq(
        [
          {
            id: 11,
            title: 'Alice',
            authors: ['Lewis Carroll'],
            languages: ['en'],
            download_count: 42,
            formats: { 'application/epub+zip' => 'https://example.org/alice.epub' },
          },
        ]
      )
    end
  end

  describe '#download' do
    let(:book) do
      {
        id: 11,
        title: 'Alice in Wonderland',
        formats: { 'application/epub+zip' => 'https://example.org/alice.epub' },
      }
    end

    it 'downloads epub and reports non-existing result' do
      progress = []
      allow(client).to receive(:download) do |_url, _dest_path, &block|
        block&.call(1, 2)
        block&.call(2, 2)
      end

      result = service.download(book) do |done, total|
        progress << [done, total]
      end

      expect(client).to have_received(:download).with('https://example.org/alice.epub', result[:path])
      expect(result[:existing]).to be(false)
      expect(progress).to eq([[1, 2], [2, 2]])
    end

    it 'returns existing when destination file already exists' do
      dest_path = File.join(downloads_root, 'alice-in-wonderland-11.epub')
      FileUtils.mkdir_p(downloads_root)
      File.binwrite(dest_path, 'existing')
      allow(client).to receive(:download)

      result = service.download(book)

      expect(result).to eq(path: dest_path, existing: true)
      expect(client).not_to have_received(:download)
    end

    it 'raises when book has no epub format' do
      expect do
        service.download({ id: 7, title: 'No Epub', formats: { 'text/plain' => 'https://example.org/noepub.txt' } })
      end.to raise_error(described_class::DownloadError, /No EPUB format available/)
    end
  end
end
