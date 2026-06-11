# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::CachePointerManager do
  around do |example|
    Dir.mktmpdir do |dir|
      example.metadata[:dir] = dir
      example.run
    end
  end

  def manager(example)
    described_class.new(File.join(example.metadata[:dir], 'pointer.json'))
  end

  it 'round-trips a valid pointer' do |example|
    mgr = manager(example)
    pointer = {
      'format' => described_class::POINTER_FORMAT,
      'version' => described_class::POINTER_VERSION,
      'sha256' => 'a' * 64,
      'source_path' => '/tmp/book.epub',
      'generated_at' => 123.0,
      'engine' => 'json',
    }

    expect(mgr.write(pointer)).not_to be(false)
    expect(mgr.read).to eq(pointer)
  end

  it 'returns nil instead of raising when the pointer file is corrupt JSON' do |example|
    path = File.join(example.metadata[:dir], 'pointer.json')
    File.binwrite(path, '{ not valid json')
    mgr = described_class.new(path)

    result = :unset
    expect { result = mgr.read }.not_to raise_error
    expect(result).to be_nil
  end

  it 'returns nil when the pointer file holds the wrong shape' do |example|
    path = File.join(example.metadata[:dir], 'pointer.json')
    File.binwrite(path, JSON.generate('a string, not an object'))
    mgr = described_class.new(path)

    expect(mgr.read).to be_nil
  end
end
