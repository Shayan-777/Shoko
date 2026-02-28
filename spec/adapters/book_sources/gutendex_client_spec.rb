# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'webmock/rspec'

RSpec.describe Shoko::Adapters::BookSources::GutendexClient do
  let(:client) { described_class.new }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.allow_net_connect!
  end

  describe '#search' do
    it 'requests the search endpoint with encoded query and parses json' do
      payload = {
        'count' => 1,
        'next' => nil,
        'previous' => nil,
        'results' => [{ 'id' => 1342, 'title' => 'Pride and Prejudice' }],
      }

      request = stub_request(:get, 'https://gutendex.com/books?search=pride+and+prejudice')
                .to_return(status: 200, body: JSON.generate(payload), headers: { 'Content-Type' => 'application/json' })

      result = client.search(query: 'pride and prejudice')

      expect(request).to have_been_requested.once
      expect(result['count']).to eq(1)
      expect(result['results'].first['id']).to eq(1342)
    end

    it 'follows redirects when searching' do
      stub_request(:get, 'https://gutendex.com/books?search=austen')
        .to_return(status: 302, headers: { 'Location' => '/books/?search=austen&page=2' })
      stub_request(:get, 'https://gutendex.com/books/?search=austen&page=2')
        .to_return(status: 200, body: JSON.generate({ 'count' => 2, 'results' => [] }))

      result = client.search(query: 'austen')

      expect(result['count']).to eq(2)
    end

    it 'raises a helpful error for invalid json' do
      stub_request(:get, 'https://gutendex.com/books?search=broken')
        .to_return(status: 200, body: '{"count":')

      expect { client.search(query: 'broken') }
        .to raise_error(described_class::Error, /Invalid JSON response/)
    end
  end

  describe '#download' do
    it 'downloads bytes to disk and reports progress' do
      stub_request(:get, 'https://gutendex.com/media/book.epub')
        .to_return(status: 200, body: 'abcdef', headers: { 'Content-Length' => '6' })

      Dir.mktmpdir do |dir|
        dest_path = File.join(dir, 'book.epub')
        progress = []

        client.download('/media/book.epub', dest_path) do |done, total|
          progress << [done, total]
        end

        expect(File.binread(dest_path)).to eq('abcdef')
        expect(progress).not_to be_empty
        expect(progress.last).to eq([6, 6])
      end
    end
  end
end
