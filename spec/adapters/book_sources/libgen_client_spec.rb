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

  describe '#search' do
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

    it 'parses libgen-compatible html into normalized book hashes' do
      html = <<~HTML
        <html>
          <body>
            <table id="tablelibgen">
              <thead>
                <tr>
                  <th>ID <a href="/index.php?order=f_id">&#8597;</a></th>
                  <th>Author(s) <a href="/index.php?order=author">&#8597;</a></th>
                  <th>Publisher <a href="/index.php?order=publisher">&#8597;</a></th>
                  <th>Year <a href="/index.php?order=year">&#8597;</a></th>
                  <th>Language</th>
                  <th>Pages</th>
                  <th>Size <a href="/index.php?order=filesize">&#8597;</a></th>
                  <th>Ext. <a href="/index.php?order=extension">&#8597;</a></th>
                  <th>Mirrors</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    <a data-toggle="tooltip" data-placement="right" data-html="true" title="Add/Edit : 2010-05-31/2021-09-27; ID: 91373993<br>Y. test" href="edition.php?id=123">Pride and Prejudice <i></i></a><br>
                    <a data-toggle="tooltip" data-placement="right" data-html="true" title="Add/Edit : 2010-05-31/2021-09-27; ID: 91373993<br>Y. test" href="edition.php?id=123"><i><font color="green">978123</font></i></a>
                    <nobr><span class="badge badge-primary"><a data-toggle="tooltip" title="Book">b</a></span></nobr>
                  </td>
                  <td>Jane Austen</td>
                  <td>Public Domain Press</td>
                  <td>1813</td>
                  <td>English</td>
                  <td>432 / 432</td>
                  <td><a href="/file.php?id=456">1 MB</a></td>
                  <td>epub</td>
                  <td>
                    <a href="/ads.php?md5=abcdef">1</a>
                    <a href="https://mirror.example/book/abcdef">2</a>
                  </td>
                </tr>
              </tbody>
            </table>
          </body>
        </html>
      HTML

      stub_request(:get, %r{\Ahttps://books\.example/index\.php\?})
        .to_return(status: 200, body: html, headers: { 'Content-Type' => 'text/html' })

      result = client.search(query: 'pride')

      expect(result[:count]).to eq(1)
      expect(result[:results]).to eq(
        [
          {
            id: '123',
            title: 'Pride and Prejudice',
            authors: ['Jane Austen'],
            languages: ['English'],
            publisher: 'Public Domain Press',
            year: '1813',
            pages: '432 / 432',
            size: '1 MB',
            extension: 'epub',
            md5: 'abcdef',
            file_page_url: 'https://books.example/file.php?id=456',
            mirrors: ['https://books.example/ads.php?md5=abcdef', 'https://mirror.example/book/abcdef'],
          },
        ]
      )
    end

    it 'rejects short libgen queries' do
      expect { client.search(query: 'ab') }
        .to raise_error(described_class::Error, /at least 3 characters/)
    end
  end

  describe '#resolve_download_url' do
    it 'extracts a direct download link from the first available mirror page' do
      stub_request(:get, 'https://books.example/ads.php?md5=abcdef')
        .to_return(status: 200, body: '<html><body><a href="/get.php?md5=abcdef&key=1">GET</a></body></html>')

      url = client.resolve_download_url(mirrors: ['https://books.example/ads.php?md5=abcdef'])

      expect(url).to eq('https://books.example/get.php?md5=abcdef&key=1')
    end

    it 'falls back to the file page when mirrors are absent' do
      url = client.resolve_download_url(file_page_url: 'https://books.example/file.php?id=456')

      expect(url).to eq('https://books.example/file.php?id=456')
    end
  end

  describe '#download' do
    it 'downloads bytes to disk and reports progress' do
      stub_request(:get, 'https://books.example/get.php?md5=abcdef&key=1')
        .to_return(status: 200, body: 'abcdef', headers: { 'Content-Length' => '6' })

      Dir.mktmpdir do |dir|
        dest_path = File.join(dir, 'book.epub')
        progress = []

        client.download('https://books.example/get.php?md5=abcdef&key=1', dest_path) do |done, total|
          progress << [done, total]
        end

        expect(File.binread(dest_path)).to eq('abcdef')
        expect(progress.last).to eq([6, 6])
      end
    end
  end
end
