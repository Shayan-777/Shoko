# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'webmock/rspec'

RSpec.describe Shoko::Adapters::Storage::DictionaryCatalogService do
  let(:service) { described_class.new }
  let(:base_url) { described_class::BASE_URL }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.allow_net_connect!
  end

  describe '#list_remote' do
    it 'parses dictionary index rows into catalog entries' do
      body = <<~HTML
        <html><body><pre>
        <a href="en-de.sqlite3">en-de.sqlite3</a> 21-Nov-2025 07:27 2M
        <a href="de-en.sqlite3">de-en.sqlite3</a> 21-Nov-2025 07:28 3M
        <a href="README.txt">README.txt</a>
        </pre></body></html>
      HTML
      stub_request(:get, base_url).to_return(status: 200, body: body)

      items = service.list_remote

      expect(items.map { |item| item[:name] }).to eq(%w[de-en.sqlite3 en-de.sqlite3])
      expect(items.first).to include(source: 'de', target: 'en', size: '3M')
      expect(items.last).to include(source: 'en', target: 'de', size: '2M')
      expect(items.first[:url]).to eq("#{base_url}de-en.sqlite3")
    end

    it 'raises CatalogError on request failures' do
      stub_request(:get, base_url).to_timeout

      expect { service.list_remote }.to raise_error(described_class::CatalogError)
    end

    it 'aborts an oversized index response at the byte ceiling' do
      stub_const("#{described_class}::MAX_INDEX_BODY_BYTES", 64)
      stub_request(:get, base_url).to_return(status: 200, body: 'x' * 128)

      expect { service.list_remote }
        .to raise_error(described_class::CatalogError, /Index response exceeded 64 bytes/)
    end
  end

  describe '#download' do
    it 'follows redirects, writes file, and reports progress' do
      source_url = "#{base_url}en-de.sqlite3"
      redirect_url = 'https://download.wikdict.com/files/en-de.sqlite3'

      stub_request(:get, source_url)
        .to_return(status: 302, headers: { 'Location' => '/files/en-de.sqlite3' })
      stub_request(:get, redirect_url)
        .to_return(status: 200, body: 'sqlite', headers: { 'Content-Length' => '6' })

      Dir.mktmpdir do |dir|
        progress = []
        entry = { name: 'en-de.sqlite3', url: source_url }
        result = service.download(entry, dir) { |done, total| progress << [done, total] }

        dest_path = File.join(dir, 'en-de.sqlite3')
        expect(result).to eq(path: dest_path, existing: false)
        expect(File.binread(dest_path)).to eq('sqlite')
        expect(progress).not_to be_empty
        expect(progress.last).to eq([6, 6])
      end
    end

    it 'aborts downloads that exceed the byte ceiling and leaves no file behind' do
      stub_const("#{described_class}::MAX_DOWNLOAD_BYTES", 4)
      source_url = "#{base_url}en-de.sqlite3"
      stub_request(:get, source_url).to_return(status: 200, body: 'sqlite-too-big')

      Dir.mktmpdir do |dir|
        entry = { name: 'en-de.sqlite3', url: source_url }

        expect { service.download(entry, dir) }
          .to raise_error(described_class::CatalogError, /exceeded 4 bytes/)

        dest_path = File.join(dir, 'en-de.sqlite3')
        expect(File.exist?(dest_path)).to be(false)
        expect(File.exist?("#{dest_path}.part")).to be(false)
      end
    end

    it 'returns existing when file already exists and skips network download' do
      Dir.mktmpdir do |dir|
        dest_path = File.join(dir, 'en-de.sqlite3')
        File.binwrite(dest_path, 'cached')

        entry = { name: 'en-de.sqlite3' }
        result = service.download(entry, dir)

        expect(result).to eq(path: dest_path, existing: true)
      end
    end

    it 'confines a hostile catalog filename to the destination directory' do
      source_url = "#{base_url}en-de.sqlite3"
      stub_request(:get, source_url)
        .to_return(status: 200, body: 'sqlite', headers: { 'Content-Length' => '6' })

      Dir.mktmpdir do |dir|
        dest_dir = File.join(dir, 'dictionaries')
        FileUtils.mkdir_p(dest_dir)
        entry = { name: '../../escaped.sqlite3', url: source_url }

        result = service.download(entry, dest_dir)

        expect(result[:path]).to eq(File.join(dest_dir, 'escaped.sqlite3'))
        expect(File.exist?(File.join(dir, 'escaped.sqlite3'))).to be(false)
        expect(File.binread(File.join(dest_dir, 'escaped.sqlite3'))).to eq('sqlite')
      end
    end

    it 'does not write error bodies to the destination on failed downloads' do
      source_url = "#{base_url}en-de.sqlite3"
      stub_request(:get, source_url)
        .to_return(status: 404, body: '<html>not found</html>')

      Dir.mktmpdir do |dir|
        dest_path = File.join(dir, 'en-de.sqlite3')

        expect { service.download({ name: 'en-de.sqlite3', url: source_url }, dir) }
          .to raise_error(described_class::CatalogError, /404/)

        expect(File.exist?(dest_path)).to be(false)
        expect(File.exist?("#{dest_path}.part")).to be(false)
      end
    end
  end
end
