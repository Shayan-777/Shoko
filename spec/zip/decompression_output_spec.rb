# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'zlib'

RSpec.describe Shoko::Zip::DecompressionOutput do
  def entry(compressed_size: 1, uncompressed_size: 1)
    Shoko::Zip::Entry.new(
      name: 'hostile.txt',
      compressed_size:,
      uncompressed_size:,
      crc32: nil,
      compression_method: 8,
      gp_flags: 0,
      local_header_offset: 0
    )
  end

  def limits(max_entry: 6, max_total: 12, max_compressed: 12)
    Shoko::Zip::SizeLimits.new(
      max_entry_uncompressed: max_entry,
      max_entry_compressed: max_compressed,
      max_total_uncompressed: max_total
    )
  end

  def non_appendable_chunk(bytesize)
    Object.new.tap do |chunk|
      chunk.define_singleton_method(:bytesize) { bytesize }
      chunk.define_singleton_method(:to_str) { raise 'oversized chunk reached the accumulator' }
    end
  end

  def raw_deflate(text)
    deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    deflater.deflate(text, Zlib::FINISH)
  ensure
    deflater&.close
  end

  it 'checks each prospective chunk before appending it' do
    output = described_class.new(limits, entry)

    expect { output.append(non_appendable_chunk(7)) }
      .to raise_error(Shoko::Zip::Error, /too large after decompression/)
  end

  it 'includes already accumulated bytes in the prospective ceiling check' do
    output = described_class.new(limits, entry)
    output.append('1234')

    expect { output.append(non_appendable_chunk(3)) }
      .to raise_error(Shoko::Zip::Error, /too large after decompression/)
  end

  it 'checks bytes returned by inflater finish before appending them' do
    output = described_class.new(limits, entry)
    output.append('1234')
    inflater = instance_double(Zlib::Inflate, finish: non_appendable_chunk(3))

    expect { output.finalize(inflater) }
      .to raise_error(Shoko::Zip::Error, /too large after decompression/)
  end

  it 'returns the complete output when every chunk remains inside the ceiling' do
    output = described_class.new(limits, entry)
    output.append('1234')
    inflater = instance_double(Zlib::Inflate, finish: '56')

    expect(output.finalize(inflater)).to eq('123456')
  end

  it 'rejects a deflate bomb whose declared size understates its expanded output' do
    compressed = raw_deflate('a' * 1_000_000)
    archive_limits = limits(max_entry: 4096, max_total: 8192, max_compressed: 4096)
    hostile_entry = entry(compressed_size: compressed.bytesize, uncompressed_size: 1)
    decompressor = Shoko::Zip::EntryDecompressor.new(StringIO.new(compressed), archive_limits)

    expect(compressed.bytesize).to be < 4096
    expect { decompressor.inflate_deflated_entry(hostile_entry) }
      .to raise_error(Shoko::Zip::Error, /too large after decompression/)
  end
end
