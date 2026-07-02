# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'webmock/rspec'
require 'open3'

RSpec.describe Shoko::Adapters::BookSources::LibgenClient do
  let(:client) { described_class.new(base_url: 'https://books.example') }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.allow_net_connect!
  end

  def search_html(ids)
    ids.map { |id| %(<a href="edition.php?id=#{id}">Result #{id}</a>) }.join("\n")
  end

  def stub_index(page:, body:, query: 'pride and prejudice')
    stub_request(:get, 'https://books.example/index.php')
      .with(query: { 'req' => query, 'curtab' => 'e', 'res' => '50', 'page' => page.to_s })
      .to_return(status: 200, body: body)
  end

  def stub_editions(ids:, body:)
    stub_request(:get, 'https://books.example/json.php')
      .with(query: { 'object' => 'e', 'ids' => ids,
                     'fields' => described_class::EDITION_FIELDS, 'addkeys' => '101' })
      .to_return(status: 200, body: JSON.generate(body))
  end

  def stub_files(ids:, body:)
    stub_request(:get, 'https://books.example/json.php')
      .with(query: { 'object' => 'f', 'ids' => ids, 'fields' => described_class::FILE_FIELDS })
      .to_return(status: 200, body: JSON.generate(body))
  end

  def edition(title:, author: 'Jane Austen', files: {})
    {
      'title' => title, 'author' => author, 'year' => '1813',
      'publisher' => 'Public Domain Press', 'pages' => '432',
      'add' => { '101' => { 'key' => '101', 'name_en' => 'Language', 'value' => 'English' } },
      'files' => files,
    }
  end

  it 'can be instantiated in an isolated ruby process without prior uri requires' do
    root = File.expand_path('../../..', __dir__)
    code = <<~RUBY
      $LOAD_PATH.unshift(File.join(#{root.inspect}, 'lib'))
      require 'shoko/adapters/book_sources/libgen_client'
      client = Shoko::Adapters::BookSources::LibgenClient.new(base_url: 'https://books.example')
      puts client.class.name
    RUBY

    stdout, stderr, status = Open3.capture3('ruby', '-e', code)

    expect(status.success?).to be(true), stderr
    expect(stdout.strip).to eq('Shoko::Adapters::BookSources::LibgenClient')
  end

  describe '#search' do
    it 'scrapes edition ids and hydrates full records through the JSON API in relevance order' do
      # The search page lists 30, 10, 20 (with a duplicate); the JSON API
      # answers in ascending id order — results must keep the search order.
      stub_index(page: 1, body: search_html(%w[30 10 30 20]))
      stub_editions(
        ids: '30,10,20',
        body: {
          '10' => edition(title: 'Emma', files: { 'a' => { 'f_id' => '110' } }),
          '20' => edition(title: 'Persuasion', files: { 'b' => { 'f_id' => '120' } }),
          '30' => edition(title: 'Pride and Prejudice', author: 'Jane Austen; Some Editor',
                          files: { 'c' => { 'f_id' => '130' } }),
        }
      )
      stub_files(
        ids: '110,120,130',
        body: {
          '110' => { 'md5' => 'a' * 32, 'extension' => 'EPUB', 'filesize' => '1048576' },
          '120' => { 'md5' => 'b' * 32, 'extension' => 'pdf', 'filesize' => '2097152' },
          '130' => { 'md5' => 'C' * 32, 'extension' => 'epub', 'filesize' => '524288' },
        }
      )

      result = client.search(query: 'pride and prejudice')

      expect(result[:count]).to eq(3)
      expect(result[:next]).to be_nil
      expect(result[:previous]).to be_nil
      expect(result[:results].map { |book| book[:id] }).to eq(%w[30 10 20])
      expect(result[:results].first).to eq(
        id: '30',
        title: 'Pride and Prejudice',
        authors: ['Jane Austen', 'Some Editor'],
        languages: ['English'],
        publisher: 'Public Domain Press',
        year: '1813',
        pages: '432',
        size: '512 KB',
        extension: 'epub',
        md5: 'c' * 32
      )
      expect(result[:results][1][:size]).to eq('1.0 MB')
    end

    it 'prefers reader-friendly formats when an edition offers several files' do
      stub_index(page: 1, body: search_html(%w[7]), query: 'emma')
      stub_editions(
        ids: '7',
        body: { '7' => edition(title: 'Emma', files: { 'a' => { 'f_id' => '1' }, 'b' => { 'f_id' => '2' } }) }
      )
      stub_files(
        ids: '1,2',
        body: {
          '1' => { 'md5' => 'd' * 32, 'extension' => 'pdf', 'filesize' => '10' },
          '2' => { 'md5' => 'e' * 32, 'extension' => 'epub', 'filesize' => '20' },
        }
      )

      result = client.search(query: 'emma')

      expect(result[:results].length).to eq(1)
      expect(result[:results].first[:extension]).to eq('epub')
      expect(result[:results].first[:md5]).to eq('e' * 32)
    end

    it 'matches file rows even when the API returns numeric file ids' do
      stub_index(page: 1, body: search_html(%w[7]), query: 'emma')
      stub_editions(
        ids: '7',
        body: { '7' => edition(title: 'Emma', files: { 'a' => { 'f_id' => 110 } }) }
      )
      stub_files(ids: '110', body: { '110' => { 'md5' => 'a' * 32, 'extension' => 'epub', 'filesize' => '9' } })

      result = client.search(query: 'emma')

      expect(result[:results].first[:extension]).to eq('epub')
      expect(result[:results].first[:md5]).to eq('a' * 32)
    end

    it 'uses the md5 carried on the files subarray when no file row resolves' do
      stub_index(page: 1, body: search_html(%w[7]), query: 'emma')
      stub_editions(
        ids: '7',
        body: { '7' => edition(title: 'Emma', files: { 'a' => { 'md5' => 'F' * 32 } }) }
      )

      result = client.search(query: 'emma')

      expect(result[:results].first[:md5]).to eq('f' * 32)
      expect(result[:results].first[:extension]).to eq('')
    end

    it 'drops editions without any downloadable file' do
      stub_index(page: 1, body: search_html(%w[7 8]), query: 'emma')
      stub_editions(
        ids: '7,8',
        body: {
          '7' => edition(title: 'No Files'),
          '8' => edition(title: 'Has File', files: { 'a' => { 'f_id' => '9' } }),
        }
      )
      stub_files(ids: '9', body: { '9' => { 'md5' => 'a' * 32, 'extension' => 'epub', 'filesize' => '5' } })

      result = client.search(query: 'emma')

      expect(result[:count]).to eq(2)
      expect(result[:results].map { |book| book[:title] }).to eq(['Has File'])
    end

    it 'returns an empty page when the search matches nothing' do
      stub_index(page: 1, body: '<html>No files were found</html>', query: 'zebra quantum payload')

      result = client.search(query: 'zebra quantum payload')

      expect(result).to eq(count: 0, next: nil, previous: nil, results: [])
    end

    it 'pages forward and back through mirror-independent tokens' do
      first_page_ids = (1..50).map(&:to_s)
      stub_index(page: 1, body: search_html(first_page_ids))
      stub_editions(ids: first_page_ids.join(','), body: {})
      stub_index(page: 2, body: search_html(%w[51]))
      stub_editions(ids: '51', body: {})

      first = client.search(query: 'pride and prejudice')

      expect(first[:next]).to eq('/index.php?req=pride+and+prejudice&page=2')
      expect(first[:previous]).to be_nil

      second = client.search(page_url: first[:next])

      expect(second[:next]).to be_nil
      expect(second[:previous]).to eq('/index.php?req=pride+and+prejudice&page=1')
    end

    it 'rejects short queries without touching the network' do
      expect { client.search(query: 'ab') }
        .to raise_error(described_class::Error, /at least 3 characters/)
    end

    it 'rejects page tokens without a query' do
      expect { client.search(page_url: '/index.php?page=2') }
        .to raise_error(described_class::Error, /Invalid page token/)
    end

    it 'translates an API error payload into a clear failure' do
      stub_index(page: 1, body: search_html(%w[1]))
      stub_request(:get, 'https://books.example/json.php')
        .with(query: hash_including('object' => 'e'))
        .to_return(status: 200, body: '{"error":"SQL ERROR"}')

      expect { client.search(query: 'pride and prejudice') }
        .to raise_error(described_class::Error, /SQL ERROR/)
    end

    it 'translates invalid JSON into a clear failure' do
      stub_index(page: 1, body: search_html(%w[1]))
      stub_request(:get, 'https://books.example/json.php')
        .with(query: hash_including('object' => 'e'))
        .to_return(status: 200, body: 'not json')

      expect { client.search(query: 'pride and prejudice') }
        .to raise_error(described_class::Error, /Invalid JSON/)
    end
  end

  describe 'mirror failover' do
    let(:client) { described_class.new(mirrors: ['https://down.example', 'https://up.example']) }

    it 'falls over to the next mirror and promotes the working one' do
      stub_request(:get, %r{\Ahttps://down\.example/}).to_timeout
      stub_request(:get, 'https://up.example/index.php')
        .with(query: hash_including('req' => 'emma'))
        .to_return(status: 200, body: '')

      client.search(query: 'emma')
      client.search(query: 'emma')

      expect(WebMock).to have_requested(:get, %r{\Ahttps://down\.example/}).once
      expect(WebMock).to have_requested(:get, %r{\Ahttps://up\.example/index\.php}).twice
    end

    it 'reports every mirror when all of them fail' do
      stub_request(:get, %r{\Ahttps://down\.example/}).to_timeout
      stub_request(:get, %r{\Ahttps://up\.example/}).to_return(status: 500)

      expect { client.search(query: 'emma') }
        .to raise_error(described_class::Error, /All mirrors failed.*down\.example.*up\.example/m)
    end
  end

  describe '#resolve_download_url' do
    let(:md5) { 'a' * 32 }

    it 'resolves the keyed get.php link through the ads.php chain' do
      stub_request(:get, "https://books.example/ads.php?md5=#{md5}")
        .to_return(status: 200, body: %(<a href="get.php?md5=#{md5}&key=ABC123def">GET</a>))

      url = client.resolve_download_url(md5: md5)

      expect(url).to eq("https://books.example/get.php?md5=#{md5}&key=ABC123def")
    end

    it 'raises when the download page offers no keyed link' do
      stub_request(:get, "https://books.example/ads.php?md5=#{md5}")
        .to_return(status: 200, body: '<html>no download here</html>')

      expect { client.resolve_download_url(md5: md5) }
        .to raise_error(described_class::Error, /file may be unavailable/)
    end

    it 'rejects a missing or malformed md5 without any request' do
      expect { client.resolve_download_url({}) }
        .to raise_error(described_class::Error, /Invalid md5/)
      expect { client.resolve_download_url(md5: 'not-a-hash') }
        .to raise_error(described_class::Error, /Invalid md5/)
    end
  end

  describe '#download' do
    let(:url) { "https://books.example/get.php?md5=#{'a' * 32}&key=1" }

    it 'streams bytes to disk and reports progress' do
      stub_request(:get, url)
        .to_return(status: 200, body: 'abcdef', headers: { 'Content-Length' => '6' })

      Dir.mktmpdir do |dir|
        dest_path = File.join(dir, 'book.epub')
        progress = []

        client.download(url, dest_path) { |done, total| progress << [done, total] }

        expect(File.binread(dest_path)).to eq('abcdef')
        expect(progress.last).to eq([6, 6])
      end
    end

    it 'follows redirects to the CDN before streaming' do
      stub_request(:get, url)
        .to_return(status: 302, headers: { 'Location' => 'https://cdn.example/book.epub' })
      stub_request(:get, 'https://cdn.example/book.epub')
        .to_return(status: 200, body: 'cdn-bytes')

      Dir.mktmpdir do |dir|
        dest_path = File.join(dir, 'book.epub')

        client.download(url, dest_path)

        expect(File.binread(dest_path)).to eq('cdn-bytes')
      end
    end

    it 'leaves no file behind when the stream is interrupted mid-download' do
      stub_request(:get, url)
        .to_return(status: 200, body: 'abcdef', headers: { 'Content-Length' => '6' })

      Dir.mktmpdir do |dir|
        dest_path = File.join(dir, 'book.epub')
        interruption = Class.new(StandardError)

        expect do
          client.download(url, dest_path) { |_done, _total| raise interruption, 'cancelled mid-stream' }
        end.to raise_error(interruption)

        expect(File.exist?(dest_path)).to be(false)
        expect(File.exist?("#{dest_path}.part")).to be(false)
      end
    end

    it 'translates a failing response into a clear error' do
      stub_request(:get, url).to_return(status: 404)

      Dir.mktmpdir do |dir|
        expect { client.download(url, File.join(dir, 'book.epub')) }
          .to raise_error(described_class::Error, /HTTP 404/)
      end
    end
  end
end
