# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'zlib'
require 'stringio'

RSpec.describe Shoko::Adapters::Rss::ArticleContentFetcher do
  let(:extractor) { instance_double(Shoko::Adapters::Rss::ArticleContentExtractor) }

  subject(:fetcher) { described_class.new(extractor: extractor, open_timeout: 1, read_timeout: 1, redirect_limit: 2) }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.allow_net_connect!
  end

  def gzip_payload(text)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) { |writer| writer.write(text) }
    io.string
  end

  it 'fetches article html, decodes gzip, and extracts content' do
    html = '<html><body><article><p>Full body</p></article></body></html>'
    stub_request(:get, 'https://example.com/post')
      .to_return(status: 200, body: gzip_payload(html), headers: { 'Content-Encoding' => 'gzip' })
    allow(extractor).to receive(:extract).with(html).and_return("Full body\n")

    result = fetcher.fetch('https://example.com/post')

    expect(result).to eq("Full body\n")
  end

  # German (and most non-English) feeds routinely link slugs containing
  # umlauts. `URI.parse` rejects those outright, so hydration failed for the
  # majority of entries and the reader fell back to the feed's short summary.
  it 'fetches an article whose URL contains non-ASCII characters' do
    html = '<html><body><article><p>Umlaut body</p></article></body></html>'
    stub_request(:get, 'https://www.dw.com/de/klassenzimmer-einschl%C3%A4gt/a-78076700')
      .to_return(status: 200, body: html)
    allow(extractor).to receive(:extract).with(html).and_return('Umlaut body')

    result = fetcher.fetch('https://www.dw.com/de/klassenzimmer-einschlägt/a-78076700')

    expect(result).to eq('Umlaut body')
  end

  it 'follows a redirect to a location containing non-ASCII characters' do
    html = '<html><body><article><p>Redirected</p></article></body></html>'
    stub_request(:get, 'https://example.com/start')
      .to_return(status: 302, headers: { 'Location' => '/de/gewässer' })
    stub_request(:get, 'https://example.com/de/gew%C3%A4sser').to_return(status: 200, body: html)
    allow(extractor).to receive(:extract).with(html).and_return('Redirected')

    expect(fetcher.fetch('https://example.com/start')).to eq('Redirected')
  end

  it 'follows redirects before extracting article content' do
    html = '<html><body><section class="body"><p>Redirected body</p></section></body></html>'
    stub_request(:get, 'https://example.com/start')
      .to_return(status: 302, headers: { 'Location' => '/post' })
    stub_request(:get, 'https://example.com/post')
      .to_return(status: 200, body: html)
    allow(extractor).to receive(:extract).with(html).and_return('Redirected body')

    result = fetcher.fetch('https://example.com/start')

    expect(result).to eq('Redirected body')
  end

  it 'raises a helpful error for unsupported url schemes' do
    expect { fetcher.fetch('ftp://example.com/post') }
      .to raise_error(Shoko::Adapters::Rss::ArticleContentFetcher::FetchError, /http or https/)
  end

  it 'aborts oversized article transfers at the byte ceiling' do
    bounded = described_class.new(extractor: extractor, max_body_bytes: 64)
    stub_request(:get, 'https://example.com/huge')
      .to_return(status: 200, body: 'a' * 200)

    expect { bounded.fetch('https://example.com/huge') }
      .to raise_error(Shoko::Adapters::Rss::ArticleContentFetcher::FetchError, /Response body exceeded 64 bytes/)
  end

  it 'translates a decompression-bomb article into a fetch error' do
    bounded = described_class.new(extractor: extractor, max_decompressed_bytes: 4096)
    stub_request(:get, 'https://example.com/bomb')
      .to_return(status: 200, body: gzip_payload('a' * 1_000_000), headers: { 'Content-Encoding' => 'gzip' })

    expect { bounded.fetch('https://example.com/bomb') }
      .to raise_error(Shoko::Adapters::Rss::ArticleContentFetcher::FetchError, /Decompressed body exceeded/)
  end
end
