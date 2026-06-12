# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Zip::File do
  def proc_fd_count
    fd_root = '/proc/self/fd'
    return nil unless Dir.exist?(fd_root)

    Dir.glob(File.join(fd_root, '*')).size
  end

  it 'exposes central directory entries through #entries' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.zip')
      SpecZipBuilderHelper.write_stored_zip(
        path,
        {
          'nested/book.fb2' => '<book/>',
          'nested/meta.txt' => 'hello'
        }
      )

      zip = described_class.open(path)
      begin
        names = zip.entries.map(&:name)

        expect(names).to eq(%w[nested/book.fb2 nested/meta.txt])
        expect(zip.entries.first).to be_a(Shoko::Zip::Entry)
      ensure
        zip.close
      end
    end
  end

  it 'fails fast when an entry payload crc32 does not match metadata' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'crc-mismatch.zip')
      SpecZipBuilderHelper.write_stored_zip(
        path,
        {
          'chapter.txt' => 'hello world'
        }
      )

      tampered = File.binread(path).sub('hello world', 'jello world')
      File.binwrite(path, tampered)

      zip = described_class.open(path)
      begin
        expect { zip.read('chapter.txt') }.to raise_error(Shoko::Zip::Error, /crc32 mismatch/i)
      ensure
        zip.close
      end
    end
  end

  it 'does not leak file descriptors across repeated invalid archive opens' do
    skip 'proc fd counters are unavailable on this platform' if proc_fd_count.nil?

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'invalid.zip')
      File.binwrite(path, 'not-a-zip')

      baseline = proc_fd_count
      30.times do
        expect { described_class.open(path) }.to raise_error(Shoko::Zip::Error)
      end

      expect(proc_fd_count).to eq(baseline)
    end
  end
end
