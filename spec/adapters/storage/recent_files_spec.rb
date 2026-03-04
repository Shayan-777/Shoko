# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::Storage::RecentFiles do
  it 'adds and clears recent file entries' do
    Dir.mktmpdir do |dir|
      config_dir = File.join(dir, 'shoko')
      recent_path = File.join(config_dir, 'recent.json')

      stub_const('Shoko::Adapters::Storage::RecentFiles::CONFIG_DIR', config_dir)
      stub_const('Shoko::Adapters::Storage::RecentFiles::RECENT_FILE', recent_path)

      described_class.add('/tmp/example.epub')
      entries = described_class.load

      expect(entries.length).to eq(1)
      expect(entries.first['path']).to eq('/tmp/example.epub')

      described_class.clear
      expect(described_class.load).to eq([])
    end
  end

  it 'raises storage error when persisted recent file payload is malformed' do
    Dir.mktmpdir do |dir|
      config_dir = File.join(dir, 'shoko')
      recent_path = File.join(config_dir, 'recent.json')
      FileUtils.mkdir_p(config_dir)
      File.write(recent_path, '{not-json')

      stub_const('Shoko::Adapters::Storage::RecentFiles::CONFIG_DIR', config_dir)
      stub_const('Shoko::Adapters::Storage::RecentFiles::RECENT_FILE', recent_path)

      expect { described_class.load }.to raise_error(Shoko::StorageError, /recent_files_load/)
    end
  end
end
