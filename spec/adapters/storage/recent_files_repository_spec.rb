# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::Storage::RecentFilesRepository do
  let(:wall_clock) do
    instance_double(
      Shoko::Application::Ports::Outbound::WallClock,
      utc_now: Time.utc(2024, 1, 1, 12, 0, 0)
    )
  end

  it 'adds and clears recent file entries' do
    Dir.mktmpdir do |dir|
      recent_path = File.join(dir, 'recent.json')
      repository = described_class.new(
        recent_file_path: recent_path,
        atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter,
        wall_clock: wall_clock
      )

      repository.add('/tmp/example.epub')
      entries = repository.load

      expect(entries.length).to eq(1)
      expect(entries.first['path']).to eq('/tmp/example.epub')
      expect(entries.first['name']).to eq('example')
      expect(entries.first['accessed']).to eq('2024-01-01T12:00:00Z')

      repository.clear
      expect(repository.load).to eq([])
    end
  end

  it 'deduplicates existing entries and moves the latest access to the top' do
    Dir.mktmpdir do |dir|
      recent_path = File.join(dir, 'recent.json')
      repository = described_class.new(
        recent_file_path: recent_path,
        atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter,
        wall_clock: wall_clock
      )

      repository.add('/tmp/example.epub')
      allow(wall_clock).to receive(:utc_now).and_return(Time.utc(2024, 1, 2, 12, 0, 0))
      repository.add('/tmp/other.epub')
      repository.add('/tmp/example.epub')

      entries = repository.load
      expect(entries.map { |entry| entry['path'] }).to eq(['/tmp/example.epub', '/tmp/other.epub'])
      expect(entries.first['accessed']).to eq('2024-01-02T12:00:00Z')
    end
  end

  it 'raises storage error when persisted recent file payload is malformed' do
    Dir.mktmpdir do |dir|
      recent_path = File.join(dir, 'recent.json')
      FileUtils.mkdir_p(dir)
      File.write(recent_path, '{not-json')

      repository = described_class.new(
        recent_file_path: recent_path,
        atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter,
        wall_clock: wall_clock
      )

      expect { repository.load }.to raise_error(Shoko::StorageError, /recent_files_load/)
    end
  end
end
