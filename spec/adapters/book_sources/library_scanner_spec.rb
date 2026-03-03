# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::LibraryScanner do
  class TestExecutor
    include Shoko::Core::Ports::Outbound::AsyncExecutor

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

  class TestBackgroundWorkerBuilder
    include Shoko::Core::Ports::Outbound::BackgroundWorkerBuilder

    attr_reader :built_with

    def initialize(executor:)
      @executor = executor
      @built_with = []
    end

    def build(name:, logger:)
      @built_with << { name: name, logger: logger }
      @executor
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
    executor = TestExecutor.new
    book_finder = instance_double('BookFinder', scan_system: [])
    builder = TestBackgroundWorkerBuilder.new(executor: executor)
    scanner = described_class.new(background_worker_builder: builder, book_finder: book_finder)
    scanner.start_scan

    expect(executor.submitted_block).not_to be_nil

    scanner.cleanup

    expect(executor.shutdown_called?).to be(true)
  end

  it 'builds owned executor from configured background worker builder' do
    owned_executor = TestExecutor.new
    builder = TestBackgroundWorkerBuilder.new(executor: owned_executor)
    book_finder = instance_double('BookFinder', scan_system: [])
    scanner = described_class.new(background_worker_builder: builder, book_finder: book_finder)

    scanner.start_scan
    expect(owned_executor.submitted_block).not_to be_nil
    expect(builder.built_with).to eq([{ name: 'library-scan-worker', logger: nil }])

    scanner.cleanup
    expect(owned_executor.shutdown_called?).to be(true)
  end
end
