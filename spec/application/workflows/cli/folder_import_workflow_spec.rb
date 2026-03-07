# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Cli::FolderImportWorkflow do
  class TestClock
    include Shoko::Core::Ports::Outbound::Clock

    def initialize(values)
      @values = values.dup
    end

    def monotonic_now
      @values.shift || 0.0
    end
  end

  class TestPathOps
    include Shoko::Core::Ports::Outbound::PathOps

    def expand_path(path, dir = nil)
      dir ? File.expand_path(path, dir) : File.expand_path(path)
    end

    def join(*parts)
      File.join(*parts)
    end

    def basename(path)
      File.basename(path)
    end

    def extname(path)
      File.extname(path)
    end
  end

  class TestScanner
    include Shoko::Core::Ports::Outbound::FolderScanner

    attr_reader :calls

    def initialize(entries)
      @entries = entries
      @calls = []
    end

    def scan(directory_path, recursive:, skip_hidden:)
      @calls << { directory_path: directory_path, recursive: recursive, skip_hidden: skip_hidden }
      @entries
    end
  end

  class TestImporter
    include Shoko::Core::Ports::Outbound::FolderImporter

    def initialize(results = {})
      @results = results
    end

    def import(path)
      outcome = @results.fetch(path, :imported)
      raise outcome if outcome.is_a?(Exception)

      outcome
    end
  end

  let(:path_ops) { TestPathOps.new }

  describe 'constructor contracts' do
    it 'rejects scanner that does not implement FolderScanner port' do
      importer = TestImporter.new
      clock = TestClock.new([0.0])

      expect do
        described_class.new(scanner: Object.new, importer: importer, clock: clock, path_ops: path_ops)
      end.to raise_error(ArgumentError, /FolderScanner/)
    end

    it 'rejects importer that does not implement FolderImporter port' do
      scanner = TestScanner.new([])
      clock = TestClock.new([0.0])

      expect do
        described_class.new(scanner: scanner, importer: Object.new, clock: clock, path_ops: path_ops)
      end.to raise_error(ArgumentError, /FolderImporter/)
    end
  end

  describe '#discover' do
    it 'normalizes and counts discovered documents by format group' do
      entries = [
        Shoko::Core::Ports::Outbound::FolderScanner::Entry.new(
          path: '/books/c.azw3',
          format_group: :kindle,
          format_extension: '.azw3'
        ),
        Shoko::Core::Ports::Outbound::FolderScanner::Entry.new(
          path: '/books/a.epub',
          format_group: :epub,
          format_extension: '.epub'
        ),
        Shoko::Core::Ports::Outbound::FolderScanner::Entry.new(
          path: '/books/b.fb2.zip',
          format_group: :fb2,
          format_extension: '.fb2.zip'
        )
      ]
      scanner = TestScanner.new(entries)
      importer = TestImporter.new
      clock = TestClock.new([0.0])

      workflow = described_class.new(scanner: scanner, importer: importer, clock: clock, path_ops: path_ops)
      report = workflow.discover('/books', recursive: true, skip_hidden: true)

      expect(scanner.calls).to eq([{ directory_path: File.expand_path('/books'), recursive: true, skip_hidden: true }])
      expect(report.total_count).to eq(3)
      expect(report.documents.map(&:path)).to eq(['/books/a.epub', '/books/b.fb2.zip', '/books/c.azw3'])
      expect(report.counts_by_group[:epub]).to eq(1)
      expect(report.counts_by_group[:fb2]).to eq(1)
      expect(report.counts_by_group[:kindle]).to eq(1)
      expect(report.counts_by_group[:pdf]).to eq(0)
      expect(report.counts_by_group[:rtf]).to eq(0)
    end

    it 'raises contract mismatch when scanner returns non-entry records' do
      scanner = TestScanner.new([{ path: '/books/a.epub' }])
      importer = TestImporter.new
      clock = TestClock.new([0.0])

      workflow = described_class.new(scanner: scanner, importer: importer, clock: clock, path_ops: path_ops)

      expect { workflow.discover('/books') }.to raise_error(ArgumentError, /Expected/)
    end
  end

  describe '#import' do
    it 'continues and reports document-scoped failures instead of aborting the batch' do
      scanner = TestScanner.new([])
      clock = TestClock.new([10.0, 12.5])
      importer = TestImporter.new(
        '/books/a.epub' => :imported,
        '/books/b.epub' => Shoko::BookParseError.new('bad book', '/books/b.epub'),
        '/books/c.epub' => :skipped
      )

      a = described_class::DocumentCandidate.new(path: '/books/a.epub', format_group: :epub, format_extension: '.epub')
      b = described_class::DocumentCandidate.new(path: '/books/b.epub', format_group: :epub, format_extension: '.epub')
      c = described_class::DocumentCandidate.new(path: '/books/c.epub', format_group: :epub, format_extension: '.epub')
      workflow = described_class.new(scanner: scanner, importer: importer, clock: clock, path_ops: path_ops)

      events = []
      report = workflow.import([a, b, c]) do |done:, total:, path:, status:|
        events << [done, total, path, status]
      end

      expect(report.total_count).to eq(3)
      expect(report.imported_count).to eq(1)
      expect(report.skipped_count).to eq(1)
      expect(report.failed_count).to eq(1)
      expect(report.failures).to eq(
        [
          described_class::ImportFailure.new(
            path: '/books/b.epub',
            error_class: 'Shoko::BookParseError',
            error_message: 'bad book'
          )
        ]
      )
      expect(report.elapsed_seconds).to eq(2.5)
      expect(events).to eq(
        [
          [1, 3, '/books/a.epub', :imported],
          [2, 3, '/books/b.epub', :failed],
          [3, 3, '/books/c.epub', :skipped]
        ]
      )
    end

    it 'fails fast when importer raises' do
      scanner = TestScanner.new([])
      clock = TestClock.new([10.0, 12.5])

      importer = TestImporter.new(
        '/books/a.epub' => :imported,
        '/books/b.epub' => :skipped,
        '/books/c.epub' => StandardError.new('broken file')
      )

      a = described_class::DocumentCandidate.new(path: '/books/a.epub', format_group: :epub, format_extension: '.epub')
      b = described_class::DocumentCandidate.new(path: '/books/b.epub', format_group: :epub, format_extension: '.epub')
      c = described_class::DocumentCandidate.new(path: '/books/c.epub', format_group: :epub, format_extension: '.epub')

      workflow = described_class.new(scanner: scanner, importer: importer, clock: clock, path_ops: path_ops)

      events = []
      expect do
        workflow.import([a, b, c]) do |done:, total:, path:, status:|
          events << [done, total, path, status]
        end
      end.to raise_error(StandardError, 'broken file')

      expect(events).to eq(
        [
          [1, 3, '/books/a.epub', :imported],
          [2, 3, '/books/b.epub', :skipped]
        ]
      )
    end

    it 'returns a report when all imports succeed' do
      scanner = TestScanner.new([])
      clock = TestClock.new([10.0, 12.5])
      importer = TestImporter.new(
        '/books/a.epub' => :imported,
        '/books/b.epub' => :skipped
      )

      a = described_class::DocumentCandidate.new(path: '/books/a.epub', format_group: :epub, format_extension: '.epub')
      b = described_class::DocumentCandidate.new(path: '/books/b.epub', format_group: :epub, format_extension: '.epub')
      workflow = described_class.new(scanner: scanner, importer: importer, clock: clock, path_ops: path_ops)

      events = []
      report = workflow.import([a, b]) do |done:, total:, path:, status:|
        events << [done, total, path, status]
      end

      expect(report.total_count).to eq(2)
      expect(report.imported_count).to eq(1)
      expect(report.skipped_count).to eq(1)
      expect(report.failed_count).to eq(0)
      expect(report.elapsed_seconds).to eq(2.5)
      expect(report.failures).to eq([])

      expect(events).to eq(
        [
          [1, 2, '/books/a.epub', :imported],
          [2, 2, '/books/b.epub', :skipped]
        ]
      )
    end
  end
end
