# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'zlib'

RSpec.describe Shoko::Adapters::Rss::BoundedHttpBody do
  def streaming_response(*chunks)
    response = Object.new
    response.define_singleton_method(:read_body) do |&block|
      chunks.each(&block)
    end
    response
  end

  def gzip(text)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) { |writer| writer.write(text) }
    io.string
  end

  def non_appendable_chunk(bytesize)
    Object.new.tap do |chunk|
      chunk.define_singleton_method(:bytesize) { bytesize }
      chunk.define_singleton_method(:to_str) { raise 'oversized chunk was appended' }
    end
  end

  describe '.read' do
    it 'accumulates chunks under the limit' do
      response = streaming_response('abc', 'def')

      expect(described_class.read(response, limit: 6)).to eq('abcdef')
    end

    it 'aborts mid-stream once the limit is exceeded' do
      yielded = []
      response = Object.new
      response.define_singleton_method(:read_body) do |&block|
        %w[aaaa bbbb cccc].each do |chunk|
          yielded << chunk
          block.call(chunk)
        end
      end

      expect { described_class.read(response, limit: 6) }
        .to raise_error(described_class::TooLarge, /exceeded 6 bytes/)
      expect(yielded).to eq(%w[aaaa bbbb])
    end

    it 'checks the incoming chunk before appending it' do
      response = streaming_response(non_appendable_chunk(7))

      expect { described_class.read(response, limit: 6) }
        .to raise_error(described_class::TooLarge, /exceeded 6 bytes/)
    end
  end

  describe '.decompress' do
    it 'passes through unencoded bodies' do
      expect(described_class.decompress('plain', '', limit: 4)).to eq('plain')
    end

    it 'decompresses gzip within the limit' do
      expect(described_class.decompress(gzip('hello'), 'gzip', limit: 64)).to eq('hello')
    end

    it 'decompresses deflate within the limit' do
      expect(described_class.decompress(Zlib::Deflate.deflate('hello'), 'deflate', limit: 64)).to eq('hello')
    end

    it 'aborts a gzip bomb at the output ceiling' do
      bomb = gzip('a' * 1_000_000)

      expect(bomb.bytesize).to be < 4096
      expect { described_class.decompress(bomb, 'gzip', limit: 4096) }
        .to raise_error(described_class::TooLarge, /Decompressed body exceeded 4096 bytes/)
    end

    it 'aborts a deflate bomb at the output ceiling' do
      bomb = Zlib::Deflate.deflate('a' * 1_000_000)

      expect { described_class.decompress(bomb, 'deflate', limit: 4096) }
        .to raise_error(described_class::TooLarge, /Decompressed body exceeded 4096 bytes/)
    end

    it 'checks gzip output chunks before appending them' do
      reader = instance_double(Zlib::GzipReader, close: nil, closed?: false)
      allow(reader).to receive(:read).and_return(non_appendable_chunk(7), nil)
      allow(Zlib::GzipReader).to receive(:new).and_return(reader)

      expect { described_class.decompress('compressed', 'gzip', limit: 6) }
        .to raise_error(described_class::TooLarge, /Decompressed body exceeded 6 bytes/)
    end

    it 'checks deflate output chunks before appending them' do
      inflater = instance_double(Zlib::Inflate, close: nil, closed?: false)
      allow(inflater).to receive(:inflate).and_yield(non_appendable_chunk(7))
      allow(Zlib::Inflate).to receive(:new).and_return(inflater)

      expect { described_class.decompress('compressed', 'deflate', limit: 6) }
        .to raise_error(described_class::TooLarge, /Decompressed body exceeded 6 bytes/)
    end

    it 'falls back to the raw body on corrupt compressed data' do
      expect(described_class.decompress('not-gzip', 'gzip', limit: 64)).to eq('not-gzip')
      expect(described_class.decompress('not-deflate', 'deflate', limit: 64)).to eq('not-deflate')
    end
  end
end
