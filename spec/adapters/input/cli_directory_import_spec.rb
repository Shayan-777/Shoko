# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Shoko::Adapters::Input::CLI do
  ImportDocument = Struct.new(:path, :format_group, :format_extension, keyword_init: true)
  DiscoveryReport = Struct.new(:directory_path, :documents, :counts_by_group, :total_count, keyword_init: true)
  ImportReport = Struct.new(:total_count, :imported_count, :skipped_count, :failed_count, :failures, :elapsed_seconds,
                            keyword_init: true)

  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  let(:application) { instance_double('UnifiedApplication', run: nil) }
  let(:app_factory) { instance_double('AppFactory') }
  let(:process_control) { instance_double('ProcessControl', terminate: nil) }

  before do
    allow(app_factory).to receive(:call).and_return(application)
  end

  def folder_context(workflow:, presenter: nil)
    presenter_factory = presenter ? -> { presenter } : nil
    Struct.new(:workflow, :progress_presenter_factory, :cli_progress_renderer).new(workflow, presenter_factory, nil)
  end

  def match_import_documents(expected)
    satisfy do |actual|
      expected_pairs = expected.map { |doc| [doc.path, doc.format_group, doc.format_extension] }
      actual_pairs = actual.map { |doc| [doc.path, doc.format_group, doc.format_extension] }
      actual.all? { |doc| doc.is_a?(Shoko::Core::Ports::Outbound::FolderScanner::Entry) } &&
        actual_pairs == expected_pairs
    end
  end

  def import_report(total_count:, imported_count:, skipped_count:, failed_count:, failures: [], elapsed_seconds: 0.1)
    ImportReport.new(
      total_count: total_count,
      imported_count: imported_count,
      skipped_count: skipped_count,
      failed_count: failed_count,
      failures: failures,
      elapsed_seconds: elapsed_seconds
    )
  end

  it 'routes directory args to folder import and exits without launching app when user selects exit' do
    Dir.mktmpdir do |books_dir|
      documents = [ImportDocument.new(path: File.join(books_dir, 'a.epub'), format_group: :epub, format_extension: '.epub')]
      report = DiscoveryReport.new(
        directory_path: books_dir,
        documents: documents,
        counts_by_group: { epub: 1 },
        total_count: 1
      )
      workflow = instance_double('FolderImportWorkflow', discover: report)
      context = folder_context(workflow: workflow)
      folder_import_factory = instance_double('FolderImportFactory', call: context)
      input = StringIO.new("3\n")
      output = StringIO.new

      expect(workflow).not_to receive(:import)
      expect(app_factory).not_to receive(:call)

      described_class.run(
        [books_dir],
        app_factory: app_factory,
        folder_import_factory: folder_import_factory,
        input: input,
        output: output,
        process_control: process_control
      )
    end
  end

  it 'imports all documents for action 1 and then opens menu mode' do
    Dir.mktmpdir do |books_dir|
      documents = [
        ImportDocument.new(path: File.join(books_dir, 'a.epub'), format_group: :epub, format_extension: '.epub'),
        ImportDocument.new(path: File.join(books_dir, 'b.pdf'), format_group: :pdf, format_extension: '.pdf'),
      ]
      report = DiscoveryReport.new(
        directory_path: books_dir,
        documents: documents,
        counts_by_group: { epub: 1, pdf: 1 },
        total_count: 2
      )
      workflow = instance_double('FolderImportWorkflow', discover: report)
      presenter = instance_double('CLIProgressPresenter', start: nil, update_status: nil, finish: nil)
      context = folder_context(workflow: workflow, presenter: presenter)
      folder_import_factory = instance_double('FolderImportFactory', call: context)
      input = StringIO.new("1\n")
      output = StringIO.new

      expect(workflow).to receive(:import).with(match_import_documents(documents)).and_return(
        import_report(total_count: 2, imported_count: 2, skipped_count: 0, failed_count: 0)
      )
      expect(presenter).to receive(:start)
      expect(presenter).to receive(:finish)
      expect(app_factory).to receive(:call).with(
        epub_path: nil,
        log_config: hash_including(:level, :output, :profile_path, :debug)
      ).and_return(application)
      expect(application).to receive(:run)

      described_class.run(
        [books_dir],
        app_factory: app_factory,
        folder_import_factory: folder_import_factory,
        input: input,
        output: output,
        process_control: process_control
      )
    end
  end

  it 'imports only the selected file type for action 2 and then opens menu mode' do
    Dir.mktmpdir do |books_dir|
      epub_doc = ImportDocument.new(path: File.join(books_dir, 'a.epub'), format_group: :epub, format_extension: '.epub')
      pdf_doc = ImportDocument.new(path: File.join(books_dir, 'b.pdf'), format_group: :pdf, format_extension: '.pdf')
      report = DiscoveryReport.new(
        directory_path: books_dir,
        documents: [epub_doc, pdf_doc],
        counts_by_group: { epub: 1, pdf: 1 },
        total_count: 2
      )
      workflow = instance_double('FolderImportWorkflow', discover: report)
      context = folder_context(workflow: workflow)
      folder_import_factory = instance_double('FolderImportFactory', call: context)
      input = StringIO.new("2\n2\n")
      output = StringIO.new

      expect(workflow).to receive(:import).with(match_import_documents([pdf_doc])).and_return(
        import_report(total_count: 1, imported_count: 1, skipped_count: 0, failed_count: 0)
      )
      expect(app_factory).to receive(:call).with(
        epub_path: nil,
        log_config: hash_including(:level, :output, :profile_path, :debug)
      ).and_return(application)
      expect(application).to receive(:run)

      described_class.run(
        [books_dir],
        app_factory: app_factory,
        folder_import_factory: folder_import_factory,
        input: input,
        output: output,
        process_control: process_control
      )
    end
  end

  it 'reprompts on invalid action input' do
    Dir.mktmpdir do |books_dir|
      documents = [ImportDocument.new(path: File.join(books_dir, 'a.epub'), format_group: :epub, format_extension: '.epub')]
      report = DiscoveryReport.new(
        directory_path: books_dir,
        documents: documents,
        counts_by_group: { epub: 1 },
        total_count: 1
      )
      workflow = instance_double('FolderImportWorkflow', discover: report)
      context = folder_context(workflow: workflow)
      folder_import_factory = instance_double('FolderImportFactory', call: context)
      input = StringIO.new("x\n9\n3\n")
      output = StringIO.new

      expect(workflow).not_to receive(:import)
      expect(app_factory).not_to receive(:call)

      described_class.run(
        [books_dir],
        app_factory: app_factory,
        folder_import_factory: folder_import_factory,
        input: input,
        output: output,
        process_control: process_control
      )

      rendered = output.string
      expect(rendered.scan('Invalid choice. Enter 1, 2, or 3.').length).to be >= 2
    end
  end

  it 'surfaces directory import contract failures as fatal external input errors' do
    Dir.mktmpdir do |books_dir|
      documents = [ImportDocument.new(path: File.join(books_dir, 'a.epub'), format_group: :epub, format_extension: '.epub')]
      report = DiscoveryReport.new(
        directory_path: books_dir,
        documents: documents,
        counts_by_group: { epub: 1 },
        total_count: 1
      )
      workflow = instance_double('FolderImportWorkflow', discover: report)
      context = folder_context(workflow: workflow)
      folder_import_factory = instance_double('FolderImportFactory', call: context)
      process_control = instance_double('ProcessControl', terminate: nil)
      input = StringIO.new("1\n")
      output = StringIO.new

      expect(workflow).to receive(:import).and_raise(ArgumentError, 'broken contract')
      expect(app_factory).not_to receive(:call)

      described_class.run(
        [books_dir],
        app_factory: app_factory,
        folder_import_factory: folder_import_factory,
        input: input,
        output: output,
        process_control: process_control
      )

      expect(process_control).to have_received(:terminate).with(2)
      expect(output.string).to include('Fatal external input error: directory import malformed input: broken contract')
    end
  end

  it 'keeps file arguments on the reader path and bypasses folder import flow' do
    Dir.mktmpdir do |dir|
      file_path = File.join(dir, 'book.epub')
      File.write(file_path, 'content')
      folder_import_factory = instance_double('FolderImportFactory')

      expect(folder_import_factory).not_to receive(:call)
      expect(app_factory).to receive(:call).with(
        epub_path: file_path,
        log_config: hash_including(:level, :output, :profile_path, :debug)
      ).and_return(application)
      expect(application).to receive(:run)

      described_class.run(
        [file_path],
        app_factory: app_factory,
        folder_import_factory: folder_import_factory,
        input: StringIO.new,
        output: StringIO.new,
        process_control: process_control
      )
    end
  end
end
