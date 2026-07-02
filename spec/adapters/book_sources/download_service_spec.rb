# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Shoko::Adapters::BookSources::DownloadService do
  let(:gutendex_client) { instance_double('GutendexClient') }
  let(:libgen_client) { instance_double('LibgenClient') }
  let(:downloads_root) { Dir.mktmpdir }
  let(:service) do
    described_class.new(
      gutendex_client: gutendex_client,
      libgen_client: libgen_client,
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
      allow(gutendex_client).to receive(:search).with(query: 'alice', page_url: nil).and_return(payload)

      result = service.search(query: 'alice', source: :gutendex)

      expect(result[:count]).to eq(1)
      expect(result[:books]).to eq(
        [
          {
            source: :gutendex,
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

    it 'normalizes libgen payloads into source-tagged book hashes' do
      payload = {
        count: 1,
        results: [
          {
            id: '123',
            title: 'The Republic',
            authors: ['Plato'],
            languages: ['en'],
            publisher: 'Public Domain',
            year: '1871',
            pages: '312',
            size: '2 MB',
            extension: 'pdf',
            md5: 'a' * 32,
          },
        ],
      }
      allow(libgen_client).to receive(:search).with(query: 'republic', page_url: nil).and_return(payload)

      result = service.search(query: 'republic', source: :libgen)

      expect(result[:books]).to eq(
        [
          {
            source: :libgen,
            id: '123',
            title: 'The Republic',
            authors: ['Plato'],
            languages: ['en'],
            publisher: 'Public Domain',
            year: '1871',
            pages: '312',
            size: '2 MB',
            extension: 'pdf',
            md5: 'a' * 32,
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
        source: :gutendex,
        formats: { 'application/epub+zip' => 'https://example.org/alice.epub' },
      }
    end

    it 'downloads epub and reports non-existing result' do
      progress = []
      allow(gutendex_client).to receive(:download) do |_url, _dest_path, &block|
        block&.call(1, 2)
        block&.call(2, 2)
      end

      result = service.download(book) do |done, total|
        progress << [done, total]
      end

      expect(gutendex_client).to have_received(:download).with('https://example.org/alice.epub', result[:path])
      expect(result[:existing]).to be(false)
      expect(progress).to eq([[1, 2], [2, 2]])
    end

    it 'returns existing when destination file already exists' do
      dest_path = File.join(downloads_root, 'alice-in-wonderland-11.epub')
      FileUtils.mkdir_p(downloads_root)
      File.binwrite(dest_path, 'existing')
      allow(gutendex_client).to receive(:download)

      result = service.download(book)

      expect(result).to eq(path: dest_path, existing: true)
      expect(gutendex_client).not_to have_received(:download)
    end

    it 'raises when book has no epub format' do
      expect do
        service.download({ id: 7, title: 'No Epub', source: :gutendex, formats: { 'text/plain' => 'https://example.org/noepub.txt' } })
      end.to raise_error(described_class::DownloadError, /No EPUB format available/)
    end

    it 'downloads libgen files using the resolved keyed link and source extension' do
      book = {
        id: '123',
        title: 'The Republic',
        source: :libgen,
        extension: 'pdf',
        md5: 'a' * 32,
      }
      allow(libgen_client).to receive(:resolve_download_url).with(book)
        .and_return("https://books.example/get.php?md5=#{'a' * 32}&key=XYZ")
      allow(libgen_client).to receive(:download)

      result = service.download(book)

      expect(libgen_client).to have_received(:download)
        .with("https://books.example/get.php?md5=#{'a' * 32}&key=XYZ", result[:path])
      expect(result[:path]).to end_with('.pdf')
    end

    context 'when remote metadata carries path-traversal payloads' do
      it 'neutralizes a malicious id so the file stays inside the downloads root' do
        book = {
          id: '../../../../tmp/pwned',
          title: 'Evil Title',
          source: :libgen,
          extension: 'epub',
          md5: 'a' * 32,
        }
        allow(libgen_client).to receive(:resolve_download_url).and_return('https://books.example/get.php?md5=abc')
        captured = nil
        allow(libgen_client).to receive(:download) { |_url, dest| captured = dest }

        result = service.download(book)

        expect(captured).to eq(result[:path])
        expect(File.dirname(File.expand_path(result[:path]))).to eq(File.expand_path(downloads_root))
        expect(File.basename(result[:path])).not_to include('/')
        expect(File.basename(result[:path])).not_to include('..')
      end

      it 'strips separators and traversal from a malicious extension' do
        book = {
          id: '7',
          title: 'Sneaky',
          source: :libgen,
          extension: '../../etc/cron.d/x',
          md5: 'a' * 32,
        }
        allow(libgen_client).to receive(:resolve_download_url).and_return('https://books.example/get.php?md5=abc')
        allow(libgen_client).to receive(:download)

        result = service.download(book)

        basename = File.basename(result[:path])
        expect(basename).not_to include('/')
        expect(basename).not_to include('..')
        expect(File.dirname(File.expand_path(result[:path]))).to eq(File.expand_path(downloads_root))
      end

      it 'falls back to a safe id when the supplied id sanitizes to nothing' do
        book = {
          id: '///',
          title: 'No Usable Id',
          source: :gutendex,
          formats: { 'application/epub+zip' => 'https://example.org/x.epub' },
        }
        allow(gutendex_client).to receive(:download)

        result = service.download(book)

        expect(File.basename(result[:path])).to eq('no-usable-id-book.epub')
      end
    end
  end
end
