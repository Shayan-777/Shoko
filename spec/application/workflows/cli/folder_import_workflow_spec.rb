# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Cli::FolderImportWorkflow do
  let(:clock) { instance_double('Clock', monotonic_now: 0.0) }

  describe '#discover' do
    it 'normalizes and counts discovered documents by format group' do
      scanner = double('FolderScanner')
      importer = double('CacheImporter', import: :imported)
      allow(scanner).to receive(:scan).and_return(
        [
          { path: '/books/c.azw3', format_group: :kindle, format_extension: '.azw3' },
          { path: '/books/a.epub', format_group: :epub, format_extension: '.epub' },
          { path: '/books/b.fb2.zip', format_group: :fb2, format_extension: '.fb2.zip' },
        ]
      )

      workflow = described_class.new(scanner: scanner, importer: importer, clock: clock)
      report = workflow.discover('/books', recursive: true, skip_hidden: true)

      expect(scanner).to have_received(:scan).with(File.expand_path('/books'), recursive: true, skip_hidden: true)
      expect(report.total_count).to eq(3)
      expect(report.documents.map(&:path)).to eq(['/books/a.epub', '/books/b.fb2.zip', '/books/c.azw3'])
      expect(report.counts_by_group[:epub]).to eq(1)
      expect(report.counts_by_group[:fb2]).to eq(1)
      expect(report.counts_by_group[:kindle]).to eq(1)
      expect(report.counts_by_group[:pdf]).to eq(0)
      expect(report.counts_by_group[:rtf]).to eq(0)
    end
  end

  describe '#import' do
    it 'tracks imported, skipped, and failed files while continuing after failures' do
      scanner = double('FolderScanner', scan: [])
      importer = double('CacheImporter')
      logger = instance_double('Logger', error: nil)
      allow(clock).to receive(:monotonic_now).and_return(10.0, 12.5)

      a = described_class::DocumentCandidate.new(path: '/books/a.epub', format_group: :epub, format_extension: '.epub')
      b = described_class::DocumentCandidate.new(path: '/books/b.epub', format_group: :epub, format_extension: '.epub')
      c = described_class::DocumentCandidate.new(path: '/books/c.epub', format_group: :epub, format_extension: '.epub')

      allow(importer).to receive(:import).with('/books/a.epub').and_return(:imported)
      allow(importer).to receive(:import).with('/books/b.epub').and_return(:skipped)
      allow(importer).to receive(:import).with('/books/c.epub').and_raise(StandardError, 'broken file')

      workflow = described_class.new(scanner: scanner, importer: importer, clock: clock, logger: logger)

      events = []
      report = workflow.import([a, b, c]) do |done:, total:, path:, status:|
        events << [done, total, path, status]
      end

      expect(report.total_count).to eq(3)
      expect(report.imported_count).to eq(1)
      expect(report.skipped_count).to eq(1)
      expect(report.failed_count).to eq(1)
      expect(report.elapsed_seconds).to eq(2.5)

      expect(report.failures.length).to eq(1)
      failure = report.failures.first
      expect(failure.path).to eq('/books/c.epub')
      expect(failure.error_class).to eq('StandardError')
      expect(failure.error_message).to eq('broken file')

      expect(events).to eq(
        [
          [1, 3, '/books/a.epub', :imported],
          [2, 3, '/books/b.epub', :skipped],
          [3, 3, '/books/c.epub', :failed],
        ]
      )
    end
  end
end
