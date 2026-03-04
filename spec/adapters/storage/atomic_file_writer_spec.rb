# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::AtomicFileWriter do
  it 'writes content atomically to the target file' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'payload.txt')

      described_class.write(path, 'hello')

      expect(File.read(path)).to eq('hello')
    end
  end

  it 'raises storage error when atomic write operation fails' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'payload.txt')

      expect do
        described_class.write_using(path) { |_io| raise IOError, 'boom' }
      end.to raise_error(Shoko::StorageError, /atomic_write/)
    end
  end
end
