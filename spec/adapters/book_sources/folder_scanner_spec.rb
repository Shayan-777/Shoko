# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::BookSources::FolderScanner do
  def write_book(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, 'ebook-content')
  end

  def build_scanner
    described_class.new(
      format_registry: Shoko::Core::BookFormats::FormatRegistry,
      book_file_probe: Shoko::Adapters::BookSources::BookFileProbe.new
    )
  end

  it 'scans recursively for supported book files' do
    Dir.mktmpdir do |dir|
      write_book(File.join(dir, 'a.epub'))
      write_book(File.join(dir, 'nested', 'b.pdf'))

      scanner = build_scanner
      results = scanner.scan(dir, recursive: true, skip_hidden: true)

      paths = results.map(&:path)
      expect(paths).to include(File.join(dir, 'a.epub'))
      expect(paths).to include(File.join(dir, 'nested', 'b.pdf'))
    end
  end

  it 'does not descend into hidden files and folders when skip_hidden is true' do
    Dir.mktmpdir do |dir|
      write_book(File.join(dir, '.hidden.epub'))
      write_book(File.join(dir, '.hidden_folder', 'inside.epub'))
      write_book(File.join(dir, 'visible.epub'))

      scanner = build_scanner
      results = scanner.scan(dir, recursive: true, skip_hidden: true)
      paths = results.map(&:path)

      expect(paths).to include(File.join(dir, 'visible.epub'))
      expect(paths).not_to include(File.join(dir, '.hidden.epub'))
      expect(paths).not_to include(File.join(dir, '.hidden_folder', 'inside.epub'))
    end
  end

  it 'includes hidden entries when skip_hidden is false' do
    Dir.mktmpdir do |dir|
      hidden = File.join(dir, '.hidden.epub')
      write_book(hidden)

      scanner = build_scanner
      results = scanner.scan(dir, recursive: true, skip_hidden: false)

      expect(results.map(&:path)).to include(hidden)
    end
  end

  it 'detects compound extensions and maps format groups' do
    Dir.mktmpdir do |dir|
      fb2_zip = File.join(dir, 'book.fb2.zip')
      kindle = File.join(dir, 'reader.azw3')
      rtf = File.join(dir, 'doc.rtf')
      write_book(fb2_zip)
      write_book(kindle)
      write_book(rtf)

      scanner = build_scanner
      results = scanner.scan(dir, recursive: true, skip_hidden: true)
      indexed = results.each_with_object({}) { |item, acc| acc[item.path] = item }

      expect(indexed[fb2_zip].format_extension).to eq('.fb2.zip')
      expect(indexed[fb2_zip].format_group).to eq(:fb2)
      expect(indexed[kindle].format_extension).to eq('.azw3')
      expect(indexed[kindle].format_group).to eq(:kindle)
      expect(indexed[rtf].format_extension).to eq('.rtf')
      expect(indexed[rtf].format_group).to eq(:rtf)
    end
  end
end
