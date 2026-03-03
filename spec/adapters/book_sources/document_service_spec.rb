# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::DocumentService do
  let(:logger) { instance_double('Logger', error: nil) }
  let(:wrapping_service) { instance_double('WrappingService') }
  let(:book_cache_pipeline) { instance_double('BookCachePipeline') }

  describe '#load_document' do
    it 'propagates non-Shoko exceptions from BookDocument construction' do
      allow(Shoko::Adapters::BookSources::BookDocument).to receive(:new).and_raise(StandardError, 'boom')

      service = described_class.new(
        '/tmp/missing.epub',
        wrapping_service,
        logger: logger,
        book_cache_pipeline: book_cache_pipeline
      )

      expect { service.load_document }.to raise_error(StandardError, /boom/)
      expect { service.load_document }.to raise_error(StandardError, /boom/)

      expect(Shoko::Adapters::BookSources::BookDocument).to have_received(:new).twice
    end
  end
end
