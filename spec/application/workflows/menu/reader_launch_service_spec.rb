# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunchService do
  class PortBookSelectionDouble
    include Shoko::Application::Ports::Outbound::MenuBookSelection

    attr_accessor :selected_book_value, :filtered_books_value

    def initialize
      @selected_book_value = nil
      @filtered_books_value = []
    end

    def selected_book
      @selected_book_value
    end

    def filtered_books
      @filtered_books_value
    end
  end

  let(:book_selection) { PortBookSelectionDouble.new }
  let(:path_resolution) do
    Object.new.tap do |obj|
      obj.extend(Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts::PathResolution)
      allow(obj).to receive(:file_exists?).and_return(true)
      allow(obj).to receive(:valid_cache_path?).and_return(true)
    end
  end
  let(:document_preparation) do
    Object.new.tap do |obj|
      obj.extend(Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts::DocumentPreparation)
      allow(obj).to receive(:ensure_reader_document_for).and_return(true)
      allow(obj).to receive(:ensure_background_worker).and_return(nil)
      allow(obj).to receive(:load_document_for).and_return(instance_double('Document'))
      allow(obj).to receive(:register_document).and_return(nil)
      allow(obj).to receive(:update_total_chapters).and_return(nil)
    end
  end
  let(:runtime_execution) do
    Object.new.tap do |obj|
      obj.extend(Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts::RuntimeExecution)
      allow(obj).to receive(:run_reader).and_return(nil)
      allow(obj).to receive(:file_not_found).and_return(nil)
      allow(obj).to receive(:handle_reader_error).and_return(nil)
    end
  end
  let(:progress_orchestration) do
    Object.new.tap do |obj|
      obj.extend(Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts::ProgressOrchestration)
      allow(obj).to receive(:load_and_open_with_progress).and_return(nil)
      allow(obj).to receive(:prepare_reader_launch).and_return(nil)
    end
  end

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        book_selection: book_selection,
        path_resolution: path_resolution,
        document_preparation: document_preparation,
        runtime_execution: runtime_execution,
        progress_orchestration: progress_orchestration
      ).validate!
    )
  end

  it 'opens selected book through progress flow when file exists' do
    book_selection.selected_book_value = Shoko::Core::Models::MenuBook.from_h(path: '/tmp/book.epub')

    expect(service).to receive(:load_and_open_with_progress).with('/tmp/book.epub')
    service.open_selected_book
  end

  it 'reports file not found for missing selected book path' do
    book_selection.selected_book_value = Shoko::Core::Models::MenuBook.from_h(path: '/tmp/missing.epub')
    allow(path_resolution).to receive(:file_exists?).with('/tmp/missing.epub').and_return(false)

    expect(runtime_execution).to receive(:file_not_found)
    service.open_selected_book
  end

  it 'delegates open_book to progress flow when file exists' do
    expect(service).to receive(:load_and_open_with_progress).with('/tmp/book.epub')
    service.open_book('/tmp/book.epub')
  end

  it 'delegates run_reader to runtime execution with ensure callback' do
    expect(runtime_execution).to receive(:run_reader).with(
      path: '/tmp/book.epub',
      ensure_reader_document_for: kind_of(Proc)
    )
    service.run_reader('/tmp/book.epub')
  end

  it 'delegates load_and_open_with_progress to progress orchestration' do
    expect(progress_orchestration).to receive(:load_and_open_with_progress).with(
      path: '/tmp/book.epub',
      prepare_reader_launch: kind_of(Method),
      run_reader: kind_of(Method)
    )
    service.load_and_open_with_progress('/tmp/book.epub')
  end

  it 'delegates cache path validation to path resolution' do
    expect(service.valid_cache_path?('/tmp/book.cache')).to be(true)
  end

  it 'delegates ensure_reader_document_for through document preparation' do
    expect(document_preparation).to receive(:ensure_reader_document_for).with(
      path: '/tmp/book.epub',
      path_resolution: path_resolution,
      on_error: kind_of(Method)
    ).and_return(true)

    expect(service.ensure_reader_document_for('/tmp/book.epub')).to be(true)
  end

  it 'rejects untyped collaborators during dependency validation' do
    expect do
      described_class::Dependencies.new(
        book_selection: book_selection,
        path_resolution: Object.new,
        document_preparation: document_preparation,
        runtime_execution: runtime_execution,
        progress_orchestration: progress_orchestration
      ).validate!
    end.to raise_error(ArgumentError, /path_resolution must implement/)
  end
end
