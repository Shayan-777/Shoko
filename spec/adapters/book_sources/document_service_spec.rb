# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::DocumentService do
  let(:logger) { instance_double('Logger', error: nil) }

  describe '#load_document' do
    it 'memoizes and reuses error document when BookDocument construction fails' do
      allow(Shoko::Adapters::BookSources::BookDocument).to receive(:new).and_raise(StandardError, 'boom')

      service = described_class.new('/tmp/missing.epub', logger: logger)

      first = service.load_document
      second = service.load_document

      expect(first).to be_a(Shoko::Adapters::BookSources::ErrorDocument)
      expect(second).to equal(first)
      expect(Shoko::Adapters::BookSources::BookDocument).to have_received(:new).once
      expect(service.chapter_at(0)).to be_a(Shoko::Adapters::BookSources::ErrorChapter)
      expect(service.get_page_content(0, 0, 5)).to include('Failed to load the ebook file:')
    end
  end
end
