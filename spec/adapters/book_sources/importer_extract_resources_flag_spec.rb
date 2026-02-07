# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Importer extract_resources flag' do
  importers = [
    Shoko::Adapters::BookSources::Epub::EpubImporter,
    Shoko::Adapters::BookSources::Fb2::Fb2Importer,
    Shoko::Adapters::BookSources::Pdf::PdfImporter,
    Shoko::Adapters::BookSources::Kindle::KindleImporter,
    Shoko::Adapters::BookSources::Rtf::RtfImporter
  ]

  importers.each do |importer_class|
    describe importer_class do
      it 'keeps extract_resources disabled by default' do
        importer = importer_class.new
        expect(importer.instance_variable_get(:@extract_resources)).to be(false)
      end

      it 'enables extract_resources only when explicitly true' do
        enabled = importer_class.new(extract_resources: true)
        disabled = importer_class.new(extract_resources: false)

        expect(enabled.instance_variable_get(:@extract_resources)).to be(true)
        expect(disabled.instance_variable_get(:@extract_resources)).to be(false)
      end
    end
  end
end
