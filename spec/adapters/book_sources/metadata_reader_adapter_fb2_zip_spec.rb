# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::MetadataReaderAdapter do
  def build_adapter
    archive_reader = Shoko::Adapters::BookSources::Archive::ZipReader
    zip_open = lambda do |path, &block|
      archive_reader.open(path, runtime_config: nil, &block)
    end
    zip_entry_reader = lambda do |path, suffix|
      archive_reader.open(path, runtime_config: nil) do |zip|
        entry = zip.entries.find { |item| item.name.downcase.end_with?(suffix.to_s.downcase) }
        entry ? zip.read(entry.name) : nil
      end
    end

    described_class.new(
      file_probe: Shoko::Adapters::Storage::FileProbeAdapter.new,
      path_ops: Shoko::Adapters::Storage::PathOpsAdapter.new,
      file_reader: ->(path) { File.binread(path) },
      text_reader: ->(path) { File.read(path, encoding: 'UTF-8') },
      zip_open: zip_open,
      zip_entry_reader: zip_entry_reader
    )
  end

  it 'extracts metadata from .fb2.zip through format registry dispatch' do
    fb2_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
        <description>
          <title-info>
            <book-title>Metadata FB2</book-title>
            <author><first-name>Ada</first-name><last-name>Lovelace</last-name></author>
            <lang>en</lang>
            <date value="1843-01-01">1843</date>
          </title-info>
        </description>
        <body>
          <section><title><p>Chapter</p></title><p>Body</p></section>
        </body>
      </FictionBook>
    XML

    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, 'metadata.fb2.zip')
      SpecZipBuilderHelper.write_stored_zip(
        zip_path,
        {
          'books/metadata.fb2' => fb2_xml
        }
      )

      adapter = build_adapter
      metadata = adapter.extract_metadata(zip_path)

      expect(metadata[:title]).to eq('Metadata FB2')
      expect(metadata[:authors]).to eq(['Ada Lovelace'])
      expect(metadata[:year]).to eq('1843')
    end
  end
end
