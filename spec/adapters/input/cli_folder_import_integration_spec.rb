# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Shoko::Adapters::Input::CLI do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  def build_clock(values)
    Class.new do
      include Shoko::Core::Ports::Outbound::Clock

      def initialize(sequence)
        @sequence = sequence.dup
      end

      def monotonic_now
        @sequence.shift || 0.0
      end
    end.new(values)
  end

  def build_path_ops
    Class.new do
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
    end.new
  end

  def build_scanner(entries)
    Class.new do
      include Shoko::Core::Ports::Outbound::FolderScanner

      def initialize(items)
        @items = items
      end

      def scan(_directory_path, recursive:, skip_hidden:)
        raise ArgumentError, 'recursive must be true' unless recursive
        raise ArgumentError, 'skip_hidden must be true' unless skip_hidden

        @items
      end
    end.new(entries)
  end

  def build_importer(results)
    Class.new do
      include Shoko::Core::Ports::Outbound::FolderImporter

      def initialize(items)
        @items = items
      end

      def import(path)
        result = @items.fetch(path, :imported)
        raise result if result.is_a?(Exception)

        result
      end
    end.new(results)
  end

  it 'runs the real folder-import workflow and reports mixed outcomes without aborting the session' do
    Dir.mktmpdir do |books_dir|
      entries = [
        Shoko::Core::Ports::Outbound::FolderScanner::Entry.new(
          path: File.join(books_dir, 'a.epub'),
          format_group: :epub,
          format_extension: '.epub'
        ),
        Shoko::Core::Ports::Outbound::FolderScanner::Entry.new(
          path: File.join(books_dir, 'b.pdf'),
          format_group: :pdf,
          format_extension: '.pdf'
        ),
        Shoko::Core::Ports::Outbound::FolderScanner::Entry.new(
          path: File.join(books_dir, 'c.epub'),
          format_group: :epub,
          format_extension: '.epub'
        ),
      ]
      workflow = Shoko::Application::Workflows::Cli::FolderImportWorkflow.new(
        scanner: build_scanner(entries),
        importer: build_importer(
          entries[0].path => :imported,
          entries[1].path => Shoko::BookParseError.new('bad pdf', entries[1].path),
          entries[2].path => :skipped
        ),
        clock: build_clock([10.0, 12.5]),
        path_ops: build_path_ops
      )
      context = Struct.new(:workflow, :progress_presenter_factory, :cli_progress_renderer).new(workflow, nil, nil)
      folder_import_factory = lambda do |log_config:|
        expect(log_config).to include(:level, :output, :profile_path, :debug)
        context
      end
      application = instance_double('UnifiedApplication', run: nil)
      app_factory = instance_double('AppFactory', call: application)
      process_control = instance_double('ProcessControl', terminate: nil)
      output = StringIO.new

      expect(application).to receive(:run)

      described_class.run(
        [books_dir],
        app_factory: app_factory,
        folder_import_factory: folder_import_factory,
        input: StringIO.new("1\n"),
        output: output,
        process_control: process_control
      )

      rendered = output.string
      expect(rendered).to include('Import completed in 2.50s')
      expect(rendered).to include('- Imported: 1')
      expect(rendered).to include('- Skipped (cached): 1')
      expect(rendered).to include('- Failed: 1')
      expect(rendered).to include('bad pdf')
      expect(process_control).not_to have_received(:terminate)
    end
  end
end
