# frozen_string_literal: true

require 'spec_helper'
require 'zlib'
require 'stringio'

RSpec.describe Shoko::Adapters::Rss::FeedFetcher do
  let(:parser) { instance_double('FeedParser') }

  subject(:fetcher) { described_class.new(parser: parser, open_timeout: 1, read_timeout: 1, redirect_limit: 2) }

  def http_response(klass, body: '', headers: {})
    code, message = case klass.name
                    when 'Net::HTTPOK' then ['200', 'OK']
                    when 'Net::HTTPFound' then ['302', 'Found']
                    when 'Net::HTTPNotModified' then ['304', 'Not Modified']
                    else ['200', 'OK']
                    end
    response = klass.new('1.1', code, message)
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, body)
    headers.each { |key, value| response[key] = value }
    response
  end

  def gzip_payload(text)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) { |writer| writer.write(text) }
    io.string
  end

  it 'normalizes bare host URLs and decodes gzip-compressed feeds' do
    xml = '<rss><channel><title>Feed</title></channel></rss>'
    allow(fetcher).to receive(:request).and_return(
      http_response(Net::HTTPOK, body: gzip_payload(xml), headers: { 'content-encoding' => 'gzip', 'etag' => 'tag-1' })
    )
    allow(parser).to receive(:parse).with(xml).and_return(title: 'Feed', site_url: 'https://example.com', articles: [])

    result = fetcher.fetch('example.com/feed.xml')

    expect(result).to include(
      not_modified: false,
      url: 'https://example.com/feed.xml',
      title: 'Feed',
      site_url: 'https://example.com',
      etag: 'tag-1',
      articles: []
    )
  end

  it 'follows redirects and resolves relative locations' do
    redirect = http_response(Net::HTTPFound, headers: { 'location' => '/rss.xml' })
    success = http_response(Net::HTTPOK, body: '<feed />')
    allow(fetcher).to receive(:request).and_return(redirect, success)
    allow(parser).to receive(:parse).with('<feed />').and_return(title: 'Redirected', site_url: nil, articles: [])

    result = fetcher.fetch('https://example.com/news')

    expect(result[:url]).to eq('https://example.com/rss.xml')
  end

  it 'returns a not-modified payload for conditional requests' do
    allow(fetcher).to receive(:request).and_return(
      http_response(Net::HTTPNotModified, headers: { 'etag' => 'new-tag', 'last-modified' => 'Mon, 06 Apr 2026 08:00:00 GMT' })
    )

    result = fetcher.fetch('https://example.com/feed.xml', etag: 'old-tag', last_modified: 'old-modified')

    expect(result).to eq(
      not_modified: true,
      url: 'https://example.com/feed.xml',
      etag: 'new-tag',
      last_modified: 'Mon, 06 Apr 2026 08:00:00 GMT',
      articles: []
    )
  end

  it 'raises a fetch error for unsupported URL schemes' do
    expect { fetcher.fetch('ftp://example.com/feed.xml') }
      .to raise_error(Shoko::Adapters::Rss::FeedFetcher::FetchError, /http or https/)
  end
end
