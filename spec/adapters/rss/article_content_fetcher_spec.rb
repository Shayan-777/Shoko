# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'zlib'
require 'stringio'

RSpec.describe Shoko::Adapters::Rss::ArticleContentFetcher do
  let(:extractor) { instance_double('ArticleContentExtractor') }

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
end
