# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'webmock/rspec'
require 'digest'

RSpec.describe Shoko::Adapters::Translation::ModelCatalogService do
  before { WebMock.disable_net_connect! }
  after { WebMock.allow_net_connect! }

  let(:records_url) { described_class::RECORDS_URL }
  let(:cdn) { described_class::ATTACHMENT_BASE_URL }

  def record(from:, to:, version:, type:, name:, location:, size: 10, hash_hex: '')
    {
      name: name, fromLang: from, toLang: to, version: version, fileType: type,
      attachment: { location: location, size: size, hash: hash_hex, filename: name },
    }
  end

  def stub_records(records)
    stub_request(:get, records_url).to_return(status: 200, body: JSON.generate(data: records))
  end


  def non_appendable_chunk(bytesize)
    Object.new.tap do |chunk|
      chunk.define_singleton_method(:bytesize) { bytesize }
      chunk.define_singleton_method(:to_str) { raise 'oversized chunk was appended' }
    end
  end

  subject(:service) { described_class.new }

  describe '#list_remote' do
    it 'offers the newest release with a shared vocabulary per pair' do
      stub_records([
                     record(from: 'et', to: 'en', version: '1.0a1', type: 'model', name: 'model.eten.a.bin', location: 'a.bin'),
                     record(from: 'et', to: 'en', version: '1.0a1', type: 'vocab', name: 'vocab.eten.a.spm', location: 'a.spm'),
                     record(from: 'et', to: 'en', version: '1.0', type: 'model', name: 'model.eten.bin', location: 'm.bin', size: 100),
                     record(from: 'et', to: 'en', version: '1.0', type: 'vocab', name: 'vocab.eten.spm', location: 'v.spm', size: 20),
                     record(from: 'et', to: 'en', version: '1.0', type: 'lex', name: 'lex.eten.bin', location: 'l.bin'),
                   ])
      packs = service.list_remote
      expect(packs.length).to eq(1)
      pack = packs.first
      expect(pack.version).to eq('1.0')
      expect(pack.model.url).to eq("#{cdn}m.bin")
      expect(pack.total_size).to eq(120)
    end

    it 'orders multi-digit prerelease suffixes naturally' do
      stub_records([
                     record(from: 'et', to: 'en', version: '1.0a2', type: 'model', name: 'm2.bin', location: 'm2.bin'),
                     record(from: 'et', to: 'en', version: '1.0a2', type: 'vocab', name: 'v2.spm', location: 'v2.spm'),
                     record(from: 'et', to: 'en', version: '1.0a10', type: 'model', name: 'm10.bin', location: 'm10.bin'),
                     record(from: 'et', to: 'en', version: '1.0a10', type: 'vocab', name: 'v10.spm', location: 'v10.spm'),
                   ])

      expect(service.list_remote.first.version).to eq('1.0a10')
    end

    it 'rejects attachments that escape the configured CDN origin' do
      stub_records([
                     record(from: 'et', to: 'en', version: '1.0', type: 'model',
                            name: 'm.bin', location: 'https://example.invalid/m.bin'),
                     record(from: 'et', to: 'en', version: '1.0', type: 'vocab', name: 'v.spm', location: 'v.spm'),
                   ])

      expect { service.list_remote }.to raise_error(described_class::CatalogError, /outside/)
    end

    it 'falls back to an older shared-vocab release when the newest is split-vocab' do
      stub_records([
                     record(from: 'en', to: 'ko', version: '2.1', type: 'model', name: 'm21.bin', location: 'm21.bin'),
                     record(from: 'en', to: 'ko', version: '2.1', type: 'srcvocab', name: 's21.spm', location: 's21.spm'),
                     record(from: 'en', to: 'ko', version: '2.1', type: 'trgvocab', name: 't21.spm', location: 't21.spm'),
                     record(from: 'en', to: 'ko', version: '2.0', type: 'model', name: 'm20.bin', location: 'm20.bin'),
                     record(from: 'en', to: 'ko', version: '2.0', type: 'vocab', name: 'v20.spm', location: 'v20.spm'),
                   ])
      packs = service.list_remote
      expect(packs.length).to eq(1)
      expect(packs.first.version).to eq('2.0')
    end

    it 'omits pairs that have no shared-vocab release at all' do
      stub_records([
                     record(from: 'en', to: 'ja', version: '2.3', type: 'model', name: 'm.bin', location: 'm.bin'),
                     record(from: 'en', to: 'ja', version: '2.3', type: 'srcvocab', name: 's.spm', location: 's.spm'),
                     record(from: 'en', to: 'ja', version: '2.3', type: 'trgvocab', name: 't.spm', location: 't.spm'),
                   ])
      expect(service.list_remote).to eq([])
    end

    it 'raises a catalog error on malformed responses' do
      stub_request(:get, records_url).to_return(status: 200, body: 'not json')
      expect { service.list_remote }.to raise_error(described_class::CatalogError)
    end

    it 'raises a catalog error on http failure' do
      stub_request(:get, records_url).to_return(status: 503, body: '')
      expect { service.list_remote }.to raise_error(described_class::CatalogError, /503/)
    end

    it 'aborts an oversized catalog response instead of buffering it' do
      oversized = 'x' * (described_class::MAX_CATALOG_BODY_BYTES + 1)
      stub_request(:get, records_url).to_return(status: 200, body: oversized)

      expect { service.list_remote }
        .to raise_error(described_class::CatalogError, /Catalog response exceeded/)
    end


    it 'checks a catalog chunk before appending it' do
      stub_const("#{described_class}::MAX_CATALOG_BODY_BYTES", 64)
      chunk = non_appendable_chunk(65)
      response = Object.new
      response.define_singleton_method(:read_body) { |&block| block.call(chunk) }

      expect { service.send(:read_bounded_catalog_body, response) }
        .to raise_error(described_class::CatalogError, /Catalog response exceeded 64 bytes/)
    end
  end

  describe '#download' do
    around do |example|
      Dir.mktmpdir('shoko-catalog') do |dir|
        @store = Shoko::Adapters::Translation::ModelStore.new(root: dir)
        example.run
      end
    end

    def build_pack(model_body, vocab_body, model_hash: nil, vocab_hash: nil)
      described_class::RemotePack.new(
        from: 'et', to: 'en', version: '1.0',
        model: described_class::RemoteFile.new(
          name: 'model.eten.bin', url: "#{cdn}m.bin", size: model_body.bytesize,
          sha256: model_hash || Digest::SHA256.hexdigest(model_body)
        ),
        vocab: described_class::RemoteFile.new(
          name: 'vocab.eten.spm', url: "#{cdn}v.spm", size: vocab_body.bytesize,
          sha256: vocab_hash || Digest::SHA256.hexdigest(vocab_body)
        )
      )
    end

    it 'downloads both files, verifies checksums, and registers the pack' do
      stub_request(:get, "#{cdn}m.bin").to_return(status: 200, body: 'model-bytes')
      stub_request(:get, "#{cdn}v.spm").to_return(status: 200, body: 'vocab-bytes')

      progress = []
      service.download(build_pack('model-bytes', 'vocab-bytes'), @store) { |done, total| progress << [done, total] }

      pack = @store.find('et', 'en')
      expect(pack).not_to be_nil
      expect(File.read(pack.model_path)).to eq('model-bytes')
      expect(File.read(pack.vocab_path)).to eq('vocab-bytes')
      expect(progress.last).to eq([22, 22])
    end

    it 'rejects a checksum mismatch and leaves no final file behind' do
      stub_request(:get, "#{cdn}m.bin").to_return(status: 200, body: 'tamper-byte')
      stub_request(:get, "#{cdn}v.spm").to_return(status: 200, body: 'vocab-bytes')

      pack = build_pack('model-bytes', 'vocab-bytes')
      expect { service.download(pack, @store) }.to raise_error(described_class::CatalogError, /Checksum/)
      expect(@store.find('et', 'en')).to be_nil
      expect(Dir.glob(File.join(@store.pack_dir('et', 'en'), '*.bin'))).to eq([])
    end

    it 'follows redirects to the payload' do
      stub_request(:get, "#{cdn}m.bin")
        .to_return(status: 302, headers: { 'Location' => "#{cdn}m2.bin" })
      stub_request(:get, "#{cdn}m2.bin").to_return(status: 200, body: 'model-bytes')
      stub_request(:get, "#{cdn}v.spm").to_return(status: 200, body: 'vocab-bytes')

      service.download(build_pack('model-bytes', 'vocab-bytes'), @store)
      expect(@store.installed?('et', 'en')).to be(true)
    end

    it 'aborts a download that exceeds its declared size before the checksum would run' do
      pack = build_pack('model-bytes', 'vocab-bytes')
      stub_request(:get, "#{cdn}m.bin").to_return(status: 200, body: 'model-bytes-plus-cdn-lies')
      stub_request(:get, "#{cdn}v.spm").to_return(status: 200, body: 'vocab-bytes')

      expect { service.download(pack, @store) }
        .to raise_error(described_class::CatalogError, /exceeded declared size/)
      expect(@store.find('et', 'en')).to be_nil
      expect(Dir.glob(File.join(@store.pack_dir('et', 'en'), '*.part'))).to eq([])
    end

    it 'rejects a truncated response even when the received bytes match their own checksum' do
      pack = build_pack('model-bytes', 'vocab-bytes')
      stub_request(:get, "#{cdn}m.bin").to_return(status: 200, body: 'short')

      expect { service.download(pack, @store) }
        .to raise_error(described_class::CatalogError, /size mismatch/)
      expect(@store.find('et', 'en')).to be_nil
    end

    it 'rejects missing checksum metadata before writing a payload' do
      pack = build_pack('model-bytes', 'vocab-bytes', model_hash: '')

      expect { service.download(pack, @store) }
        .to raise_error(described_class::CatalogError, /invalid checksum/)
      expect(a_request(:get, "#{cdn}m.bin")).not_to have_been_made
    end

    it 'rejects a catalog-declared size above the absolute ceiling' do
      stub_const("#{described_class}::MAX_FILE_BYTES", 4)
      # The catalog declares 1000 bytes; the absolute ceiling must win.
      pack = described_class::RemotePack.new(
        from: 'et', to: 'en', version: '1.0',
        model: described_class::RemoteFile.new(name: 'model.eten.bin', url: "#{cdn}m.bin", size: 1000, sha256: ''),
        vocab: described_class::RemoteFile.new(name: 'vocab.eten.spm', url: "#{cdn}v.spm", size: 1000, sha256: '')
      )
      stub_request(:get, "#{cdn}m.bin").to_return(status: 200, body: 'eight-by')
      stub_request(:get, "#{cdn}v.spm").to_return(status: 200, body: 'eight-by')

      expect { service.download(pack, @store) }
        .to raise_error(described_class::CatalogError, /invalid size/)
    end


    it 'checks a payload chunk before writing or hashing it' do
      response = Object.new
      response.define_singleton_method(:read_body) { |&block| block.call('abcde') }
      writer = instance_double(File, write: nil)
      digest = instance_double(Digest::SHA256, update: nil)
      allow(File).to receive(:open).and_yield(writer)

      expect(writer).not_to receive(:write)
      expect(digest).not_to receive(:update)
      expect { service.send(:write_body, response, '/tmp/unwritten', digest, max_bytes: 4) }
        .to raise_error(described_class::CatalogError, /exceeded declared size \(4 bytes\)/)
    end
  end
end
