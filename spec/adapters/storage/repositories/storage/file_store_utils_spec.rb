# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'

RSpec.describe Shoko::Adapters::Storage::Repositories::Storage::FileStoreUtils do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  def store_path
    File.join(@dir, 'annotations.json')
  end

  def quarantine_files
    Dir.glob("#{store_path}.corrupt-*")
  end

  it 'returns an empty hash for a missing file without quarantining' do
    expect(described_class.load_json_or_empty(store_path)).to eq({})
    expect(quarantine_files).to be_empty
  end

  it 'returns the parsed hash for a healthy object payload' do
    File.write(store_path, JSON.generate('book.epub' => %w[a b]))

    expect(described_class.load_json_or_empty(store_path)).to eq('book.epub' => %w[a b])
    expect(quarantine_files).to be_empty
  end

  context 'when the file is content-corrupt' do
    it 'quarantines unparseable JSON and preserves the original bytes' do
      original = '{ truncated: not valid ]'
      File.write(store_path, original)

      expect(described_class.load_json_or_empty(store_path)).to eq({})

      expect(File.exist?(store_path)).to be(false)
      expect(quarantine_files.size).to eq(1)
      expect(File.read(quarantine_files.first)).to eq(original)
    end

    it 'quarantines a valid-but-wrong-shape (non-object) payload' do
      File.write(store_path, JSON.generate(%w[bare array payload]))

      expect(described_class.load_json_or_empty(store_path)).to eq({})
      expect(quarantine_files.size).to eq(1)
    end

    it 'logs a warning naming the source and destination' do
      File.write(store_path, 'not json')
      logger = instance_spy('logger')

      described_class.load_json_or_empty(store_path, logger: logger)

      expect(logger).to have_received(:warn).with(
        'file_store.corrupt_file_quarantined', hash_including(from: store_path)
      )
    end

    it 'never overwrites an earlier quarantine from the same second' do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 1, 12, 0, 0))
      File.write("#{store_path}.corrupt-20260101120000", 'earlier')
      File.write(store_path, 'later corrupt')

      described_class.load_json_or_empty(store_path)

      expect(File.read("#{store_path}.corrupt-20260101120000")).to eq('earlier')
      expect(quarantine_files.size).to eq(2)
    end
  end

  context 'when the file is present but unreadable (access error, not corruption)' do
    it 'degrades to empty and leaves the file in place' do
      File.write(store_path, JSON.generate('book.epub' => []))
      allow(File).to receive(:read).with(store_path).and_raise(Errno::EACCES)

      expect(described_class.load_json_or_empty(store_path)).to eq({})

      expect(File.exist?(store_path)).to be(true)
      expect(quarantine_files).to be_empty
    end
  end
end
