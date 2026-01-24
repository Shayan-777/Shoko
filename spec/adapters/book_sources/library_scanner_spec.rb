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
    scanner = described_class.new(executor: executor)

    allow(Shoko::Adapters::BookSources::EPUBFinder).to receive(:scan_system).and_return(
      [{ 'name' => 'Book' }]
    )

    scanner.start_scan
    expect(executor.submitted_block).not_to be_nil

    executor.run
    result = scanner.process_results

    expect(result).to eq([{ 'name' => 'Book' }])
    expect(scanner.scan_status).to eq(:done)
  end

  it 'shuts down owned executors during cleanup' do
    executor = instance_double('BackgroundWorker', submit: nil, shutdown: nil)
    allow(Shoko::Adapters::Storage::BackgroundWorker).to receive(:new).and_return(executor)
    allow(Shoko::Adapters::BookSources::EPUBFinder).to receive(:scan_system).and_return([])

    scanner = described_class.new
    scanner.start_scan

    expect(executor).to have_received(:submit)

    scanner.cleanup

    expect(executor).to have_received(:shutdown)
  end
end
