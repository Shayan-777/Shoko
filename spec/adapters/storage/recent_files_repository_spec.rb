# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'

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

  # Recent history is an ancillary sidecar: corruption must cost the recent
  # list, never the menu or a book launch.
  it 'quarantines a corrupt payload and reads as empty instead of raising' do
    Dir.mktmpdir do |dir|
      recent_path = File.join(dir, 'recent.json')
      corrupt = '{not-json'
      File.write(recent_path, corrupt)

      repository = described_class.new(
        recent_file_path: recent_path,
        atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter,
        wall_clock: wall_clock
      )

      expect(repository.load).to eq([])

      quarantines = Dir.glob("#{recent_path}.corrupt-*")
      expect(quarantines.size).to eq(1)
      expect(File.read(quarantines.first)).to eq(corrupt)
    end
  end

  it 'quarantines a wrong-shape payload and keeps adding afterwards' do
    Dir.mktmpdir do |dir|
      recent_path = File.join(dir, 'recent.json')
      File.write(recent_path, JSON.generate('not' => 'an array'))

      repository = described_class.new(
        recent_file_path: recent_path,
        atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter,
        wall_clock: wall_clock
      )

      repository.add('/tmp/example.epub')

      expect(repository.load.map { |entry| entry['path'] }).to eq(['/tmp/example.epub'])
      expect(Dir.glob("#{recent_path}.corrupt-*").size).to eq(1)
    end
  end

  it 'degrades load to empty on an access error without quarantining' do
    Dir.mktmpdir do |dir|
      recent_path = File.join(dir, 'recent.json')
      File.write(recent_path, JSON.generate([]))
      allow(File).to receive(:read).with(recent_path).and_raise(Errno::EACCES)

      repository = described_class.new(
        recent_file_path: recent_path,
        atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter,
        wall_clock: wall_clock
      )

      expect(repository.load).to eq([])
      expect(Dir.glob("#{recent_path}.corrupt-*")).to be_empty
    end
  end

  it 'aborts add on an access error instead of flattening the history' do
    Dir.mktmpdir do |dir|
      recent_path = File.join(dir, 'recent.json')
      repository = described_class.new(
        recent_file_path: recent_path,
        atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter,
        wall_clock: wall_clock
      )
      repository.add('/tmp/history.epub')
      allow(File).to receive(:read).with(recent_path).and_raise(Errno::EACCES)

      expect { repository.add('/tmp/new.epub') }.to raise_error(Shoko::StorageError, /recent_files/)

      allow(File).to receive(:read).with(recent_path).and_call_original
      expect(repository.load.map { |entry| entry['path'] }).to eq(['/tmp/history.epub'])
    end
  end

  it 'does not lose entries when two threads add concurrently' do
    Dir.mktmpdir do |dir|
      recent_path = File.join(dir, 'recent.json')
      repository = described_class.new(
        recent_file_path: recent_path,
        atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter,
        wall_clock: wall_clock
      )

      barrier = Queue.new
      threads = 2.times.map do |thread_index|
        Thread.new do
          barrier.pop
          3.times { |i| repository.add("/tmp/t#{thread_index}-#{i}.epub") }
        end
      end
      2.times { barrier << true }
      threads.each(&:join)

      expect(repository.load.length).to eq(6)
    end
  end
end
