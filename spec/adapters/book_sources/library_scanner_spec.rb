# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::LibraryScanner do
  class TestExecutor
    attr_reader :submitted_block

    def submit(&block)
      @submitted_block = block
    end

    def run
      @submitted_block&.call
    end

    def shutdown(_timeout = nil)
      @shutdown_called = true
    end

    def shutdown_called?
      @shutdown_called == true
    end
  end

  it 'submits scan work to the provided executor' do
    executor = TestExecutor.new
    book_finder = instance_double('BookFinder', scan_system: [{ 'name' => 'Book' }])
    scanner = described_class.new(executor: executor, book_finder: book_finder)

    scanner.start_scan
    expect(executor.submitted_block).not_to be_nil

    executor.run
    result = scanner.process_results

    expect(result).to eq([{ 'name' => 'Book' }])
    expect(scanner.scan_status).to eq(:done)
  end

  it 'shuts down owned executors during cleanup' do
    executor = instance_double('InlineExecutor', submit: nil, shutdown: nil)
    book_finder = instance_double('BookFinder', scan_system: [])
    allow(Shoko::Core::Services::InlineExecutor).to receive(:new).and_return(executor)

    scanner = described_class.new(book_finder: book_finder)
    scanner.start_scan

    expect(executor).to have_received(:submit)

    scanner.cleanup

    expect(executor).to have_received(:shutdown)
  end

  it 'builds owned executor from factory before falling back to inline executor' do
    owned_executor = TestExecutor.new
    executor_factory = lambda do |logger:, name:|
      expect(logger).to eq(nil)
      expect(name).to eq('library-scan-worker')
      owned_executor
    end
    book_finder = instance_double('BookFinder', scan_system: [])
    scanner = described_class.new(executor_factory: executor_factory, book_finder: book_finder)

    scanner.start_scan
    expect(owned_executor.submitted_block).not_to be_nil

    scanner.cleanup
    expect(owned_executor.shutdown_called?).to be(true)
  end
end
