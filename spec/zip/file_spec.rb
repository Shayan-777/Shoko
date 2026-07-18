# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Shoko::Zip::File do
  around do |example|
    Dir.mktmpdir do |dir|
      @zip_path = File.join(dir, 'sample.zip')
      SpecZipBuilderHelper.write_stored_zip(@zip_path, 'hello.txt' => 'hello zip')
      example.run
    end
  end

  it 'opens, lists, and reads entries through the block form' do
    described_class.open(@zip_path) do |zip|
      expect(zip.entries.map(&:name)).to eq(['hello.txt'])
      expect(zip.read('hello.txt')).to eq('hello zip')
    end
  end

  describe '.close_safely' do
    it 'ignores the IO errors a close can actually raise' do
      failing = Object.new
      failing.define_singleton_method(:close) { raise IOError, 'closed stream' }

      expect { described_class.close_safely(failing) }.not_to raise_error
    end

    it 'ignores system-call errors from a close' do
      failing = Object.new
      failing.define_singleton_method(:close) { raise Errno::EBADF }

      expect { described_class.close_safely(failing) }.not_to raise_error
    end

    it 'preserves the block result when close fails after a successful read' do
      zip = described_class.new(@zip_path)
      allow(zip).to receive(:close).and_raise(IOError, 'closed stream')
      allow(described_class).to receive(:new).and_return(zip)

      result = described_class.open(@zip_path) { |z| z.read('hello.txt') }

      expect(result).to eq('hello zip')
    end
  end
end
