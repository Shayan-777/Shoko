# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'timeout'

RSpec.describe 'Book importer malformed-input properties', :parser_property do
  CASES = {
    '.epub' => [Shoko::Adapters::BookSources::Epub::EpubImporter, "PK\x03\x04".b],
    '.fb2' => [Shoko::Adapters::BookSources::Fb2::Fb2Importer, '<FictionBook>'.b],
    '.mobi' => [Shoko::Adapters::BookSources::Kindle::KindleImporter, 'BOOKMOBI'.b],
    '.rtf' => [Shoko::Adapters::BookSources::Rtf::RtfImporter, '{\\rtf1 '.b],
    '.pdf' => [Shoko::Adapters::BookSources::Pdf::PdfImporter, "%PDF-1.7\n".b],
  }.freeze
  ITERATIONS = 40
  MAX_RANDOM_BYTES = 4096
  SEED = 20_260_805

  CASES.each_with_index do |(extension, (importer_class, prefix)), format_index|
    it "fails safely for generated #{extension.delete_prefix('.').upcase} payloads" do
      random = Random.new(SEED + format_index)

      ITERATIONS.times do |iteration|
        payload = generated_payload(random, prefix)
        assert_safe_import(importer_class, extension, payload, iteration)
      end
    end
  end

  def generated_payload(random, prefix)
    random_length = random.rand(0..MAX_RANDOM_BYTES)
    prefix + random.bytes(random_length)
  end

  def assert_safe_import(importer_class, extension, payload, iteration)
    Tempfile.create(['shoko-parser-property-', extension]) do |file|
      file.binmode
      file.write(payload)
      file.flush

      result = Timeout.timeout(2) { import_or_error(importer_class, file.path) }
      safe_result = result.is_a?(Shoko::Core::Models::BookData) || result.is_a?(Shoko::Error)
      expect(safe_result).to be(true), "iteration #{iteration} escaped the importer contract"
    end
  end

  def import_or_error(importer_class, path)
    importer_class.new.import(path)
  rescue Shoko::Error => e
    e
  end
end
