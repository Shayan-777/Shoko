# frozen_string_literal: true

require 'tmpdir'
require 'spec_helper'
require 'shoko/shared/source_fingerprint'

RSpec.describe Shoko::Shared::SourceFingerprint do
  around do |example|
    Dir.mktmpdir('source-fingerprint-spec') do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  def write_file(name, content)
    path = File.join(@tmp_dir, name)
    File.binwrite(path, content)
    path
  end

  it 'returns deterministic fingerprints for the same file' do
    path = write_file('book.epub', 'chapter' * 10_000)

    first = described_class.compute(path)
    second = described_class.compute(path)

    expect(first).to eq(second)
    expect(first).to match(/\A\h{64}\z/)
  end

  it 'returns nil when the source file is not present' do
    expect(described_class.compute(nil)).to be_nil
    expect(described_class.compute('')).to be_nil
    expect(described_class.compute(File.join(@tmp_dir, 'missing.epub'))).to be_nil
  end

  it 'changes when head or tail content changes' do
    path = write_file('book.epub', ('a' * 70_000) + ('b' * 70_000))
    original = described_class.compute(path)

    File.binwrite(path, 'z' + ('a' * 69_999) + ('b' * 70_000))
    expect(described_class.compute(path)).not_to eq(original)

    File.binwrite(path, ('a' * 70_000) + ('c' * 70_000))
    expect(described_class.compute(path)).not_to eq(original)
  end

  it 'falls back to default chunk size when chunk_bytes is invalid' do
    path = write_file('book.epub', ('x' * 8_192) + ('y' * 8_192))
    expected = described_class.compute(path)

    expect(described_class.compute(path, chunk_bytes: 0)).to eq(expected)
    expect(described_class.compute(path, chunk_bytes: 'invalid')).to eq(expected)
  end
end
