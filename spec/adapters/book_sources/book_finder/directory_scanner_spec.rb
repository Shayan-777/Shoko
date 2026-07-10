# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::BookSources::BookFinder::DirectoryScanner do
  around do |example|
    Dir.mktmpdir('shoko-book-finder-home') do |home|
      with_env('HOME' => home, 'SHOKO_BOOK_SCAN_DIRS' => nil) { example.run }
    end
  end

  let(:context) { instance_double(Shoko::Adapters::BookSources::BookFinder::ScannerContext) }
  let(:book_file_probe) { instance_double(Shoko::Adapters::BookSources::BookFileProbe, book_file?: false) }

  it 'limits default scan roots to book-specific directories' do
    home = File.expand_path('~')
    config_root = File.join(home, '.config', 'shoko')
    FileUtils.mkdir_p(File.join(config_root, 'downloads'))
    FileUtils.mkdir_p(File.join(home, 'Books'))
    FileUtils.mkdir_p(File.join(home, 'Dropbox'))
    FileUtils.mkdir_p(File.join(home, 'Documents'))

    scanner = described_class.new(context, config_root: config_root, book_file_probe: book_file_probe)
    directories = scanner.send(:build_directory_list)

    expect(directories).to include(File.join(config_root, 'downloads'))
    expect(directories).to include(File.join(home, 'Books'))
    expect(directories).not_to include(home)
    expect(directories).not_to include(File.join(home, 'Dropbox'))
    expect(directories).not_to include(File.join(home, 'Documents'))
  end

  it 'allows explicit scan roots from SHOKO_BOOK_SCAN_DIRS' do
    home = File.expand_path('~')
    config_root = File.join(home, '.config', 'shoko')
    custom_a = File.join(home, 'CustomA')
    custom_b = File.join(home, 'CustomB')
    FileUtils.mkdir_p(custom_a)
    FileUtils.mkdir_p(custom_b)

    with_env('SHOKO_BOOK_SCAN_DIRS' => [custom_a, custom_b].join(File::PATH_SEPARATOR)) do
      scanner = described_class.new(context, config_root: config_root, book_file_probe: book_file_probe)
      directories = scanner.send(:build_directory_list)

      expect(directories).to include(custom_a, custom_b)
    end
  end
end
