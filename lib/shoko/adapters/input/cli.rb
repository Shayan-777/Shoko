# frozen_string_literal: true

require 'optparse'
require_relative '../../shared/version'

# Root namespace for the Shoko application.
module Shoko
  module Adapters
    module Input
      # Command-line entry adapter that parses argv and launches the application.
      class CLI
        FolderImportContext = Data.define(:workflow, :progress_presenter_factory)
        FolderImportDocument = Data.define(:path, :format_group, :format_extension)
        FolderDiscoveryReport = Data.define(:directory_path, :documents, :counts_by_group, :total_count)
        FolderImportFailure = Data.define(:path, :error_class, :error_message)
        FolderImportReport = Data.define(:total_count, :imported_count, :skipped_count, :failed_count, :failures,
                                         :elapsed_seconds)

        FORMAT_GROUP_ORDER = %i[epub pdf fb2 kindle rtf].freeze
        FORMAT_GROUP_LABELS = {
          epub: 'EPUB',
          pdf: 'PDF',
          fb2: 'FB2',
          kindle: 'Kindle',
          rtf: 'RTF',
        }.freeze
        MAX_FAILURE_LINES = 10

        class << self
          def run(argv = ARGV, app_factory:, folder_import_factory: nil, input: $stdin, output: $stdout)
            options, args = parse_options(argv)
            log_config = build_log_config(options)
            target_path = args.first

            if target_path && directory_path?(target_path) && folder_import_factory
              action = run_directory_import_session(
                target_path,
                log_config: log_config,
                folder_import_factory: folder_import_factory,
                input: input,
                output: output
              )
              return if action == :exit

              target_path = nil
            end

            app_factory.call(epub_path: target_path, log_config: log_config).run
          end

          private

          def parse_options(argv)
            options = default_options
            parser = OptionParser.new
            configure_parser(parser, options)
            parser.parse!(argv)
            [options, argv]
          end

          def default_options
            { debug: false, log_path: nil, log_level: nil, profile_path: nil }
          end

          def configure_parser(parser, options)
            parser.banner = 'Usage: shoko [options] [file_or_directory]'
            parser.version = Shoko::VERSION
            parser.on('-d', '--debug', 'Enable debug logging') { options[:debug] = true }
            parser.on('--log PATH', 'Write JSON logs to PATH instead of discarding output') do |path|
              options[:log_path] = path
            end
            parser.on('--log-level LEVEL', 'Set log level (debug, info, warn, error, fatal)') do |level|
              options[:log_level] = level
            end
            parser.on('--profile PATH', 'Write a concise performance profile to PATH') do |path|
              options[:profile_path] = path
            end
            parser.on('-h', '--help', 'Prints this help') do
              puts parser
              exit
            end
          end

          def directory_path?(path)
            File.directory?(path)
          rescue ArgumentError, SystemCallError
            raise
          end

          def run_directory_import_session(directory_path, log_config:, folder_import_factory:, input:, output:)
            context = coerce_folder_import_context(folder_import_factory.call(log_config: log_config))
            workflow = context.workflow
            report = coerce_discovery_report(workflow.discover(directory_path, recursive: true, skip_hidden: true))
            print_discovery_report(report, output)

            if report.total_count.zero?
              output.puts
              output.puts 'No supported documents were found. Opening menu...'
              return :menu
            end

            action = prompt_import_action(input, output)
            return :exit if action == :exit

            documents = select_documents_for_import(report, action, input, output)
            if documents.empty?
              output.puts
              output.puts 'No documents selected for import. Opening menu...'
              return :menu
            end

            import_report = coerce_import_report(
              execute_import(workflow: workflow, documents: documents, context: context, output: output)
            )
            print_import_summary(import_report, output)
            :menu
          rescue ArgumentError, TypeError, IOError, SystemCallError => e
            output.puts
            output.puts "Directory import failed: #{e.class}: #{e.message}"
            :menu
          end

          def coerce_folder_import_context(raw_context)
            FolderImportContext.new(
              workflow: raw_context.workflow,
              progress_presenter_factory: raw_context.progress_presenter_factory
            )
          rescue ArgumentError => e
            raise ArgumentError, "folder import context contract violation: #{e.message}"
          end

          def coerce_import_document(raw_document)
            FolderImportDocument.new(
              path: raw_document.path.to_s,
              format_group: normalize_group_value(raw_document.format_group),
              format_extension: raw_document.format_extension.to_s
            )
          rescue ArgumentError => e
            raise ArgumentError, "folder import document contract violation: #{e.message}"
          end

          def coerce_discovery_report(raw_report)
            documents = Array(raw_report.documents).map { |document| coerce_import_document(document) }
            total_count = Integer(raw_report.total_count)
            counts = normalize_counts_by_group(raw_report.counts_by_group)

            FolderDiscoveryReport.new(
              directory_path: raw_report.directory_path.to_s,
              documents: documents,
              counts_by_group: counts,
              total_count: total_count
            )
          rescue TypeError => e
            raise ArgumentError, "invalid folder discovery report: #{e.message}"
          rescue ArgumentError => e
            raise ArgumentError, "folder discovery report contract violation: #{e.message}"
          end

          def normalize_counts_by_group(raw_counts)
            raise ArgumentError, 'counts_by_group must be a Hash' unless raw_counts.is_a?(Hash)

            raw_counts.each_with_object({}) do |(raw_group, raw_count), acc|
              group = normalize_group_value(raw_group)
              acc[group] = Integer(raw_count)
            end
          rescue ArgumentError, TypeError => e
            raise ArgumentError, "invalid counts_by_group value: #{e.message}"
          end

          def coerce_import_report(raw_report)
            failures = Array(raw_report.failures).map { |failure| coerce_import_failure(failure) }

            FolderImportReport.new(
              total_count: Integer(raw_report.total_count),
              imported_count: Integer(raw_report.imported_count),
              skipped_count: Integer(raw_report.skipped_count),
              failed_count: Integer(raw_report.failed_count),
              failures: failures,
              elapsed_seconds: raw_report.elapsed_seconds.to_f
            )
          rescue TypeError => e
            raise ArgumentError, "invalid folder import report: #{e.message}"
          rescue ArgumentError => e
            raise ArgumentError, "folder import report contract violation: #{e.message}"
          end

          def coerce_import_failure(raw_failure)
            FolderImportFailure.new(
              path: raw_failure.path.to_s,
              error_class: raw_failure.error_class.to_s,
              error_message: raw_failure.error_message.to_s
            )
          rescue ArgumentError => e
            raise ArgumentError, "folder import failure contract violation: #{e.message}"
          end

          def print_discovery_report(report, output)
            output.puts
            output.puts "Directory: #{report.directory_path}"
            output.puts "Identified Documents: #{report.total_count}"

            FORMAT_GROUP_ORDER.each do |group|
              count = count_for_group(report.counts_by_group, group)
              next unless count.positive?

              label = FORMAT_GROUP_LABELS.fetch(group, group.to_s.upcase)
              noun = count == 1 ? 'file' : 'files'
              output.puts "- #{count} #{label} #{noun}"
            end
          end

          def prompt_import_action(input, output)
            loop do
              output.puts
              output.puts 'Action:'
              output.puts '1) Import all documents'
              output.puts '2) Import only one file type'
              output.puts '3) Exit'
              output.print 'Answer: '

              choice = read_choice(input)
              return :exit if choice.nil?
              return :all if choice == '1'
              return :single_type if choice == '2'
              return :exit if choice == '3'

              output.puts 'Invalid choice. Enter 1, 2, or 3.'
            end
          end

          def select_documents_for_import(report, action, input, output)
            documents = report.documents
            return documents if action == :all

            group = prompt_format_group_selection(report, input, output)
            return [] unless group

            documents.select { |document| document.format_group == group }
          end

          def prompt_format_group_selection(report, input, output)
            groups = available_format_groups(report)
            return nil if groups.empty?

            loop do
              output.puts
              output.puts 'Choose a file type:'
              groups.each_with_index do |group, index|
                label = FORMAT_GROUP_LABELS.fetch(group, group.to_s.upcase)
                count = count_for_group(report.counts_by_group, group)
                output.puts "#{index + 1}) #{label} (#{count})"
              end
              output.puts "#{groups.length + 1}) Cancel"
              output.print 'Answer: '

              choice = read_choice(input)
              return nil if choice.nil?

              selected = choice.to_i
              return groups[selected - 1] if selected.between?(1, groups.length)
              return nil if selected == groups.length + 1

              output.puts "Invalid choice. Enter a number between 1 and #{groups.length + 1}."
            end
          end

          def available_format_groups(report)
            FORMAT_GROUP_ORDER.select { |group| count_for_group(report.counts_by_group, group).positive? }
          end

          def execute_import(workflow:, documents:, context:, output:)
            presenter = build_progress_presenter(context)
            presenter.start(message: "Importing #{documents.length} document(s)...") if presenter

            workflow.import(documents) do |done:, total:, path:, status:|
              progress = total.to_i.positive? ? done.to_f / total.to_f : 1.0
              message = "Importing (#{done}/#{total}) #{File.basename(path.to_s)} [#{status}]"
              presenter.update_status(message: message, progress: progress) if presenter
            end
          ensure
            presenter.finish if presenter
            output.flush
          end

          def build_progress_presenter(context)
            factory = context.progress_presenter_factory
            return nil unless factory

            factory.call
          end

          def print_import_summary(report, output)
            output.puts
            output.puts format('Import completed in %.2fs', report.elapsed_seconds)
            output.puts "- Selected: #{report.total_count}"
            output.puts "- Imported: #{report.imported_count}"
            output.puts "- Skipped (cached): #{report.skipped_count}"
            output.puts "- Failed: #{report.failed_count}"

            failures = report.failures
            return if failures.empty?

            output.puts "Failures (showing up to #{MAX_FAILURE_LINES}):"
            failures.first(MAX_FAILURE_LINES).each_with_index do |failure, index|
              output.puts "#{index + 1}) #{failure.path} (#{failure.error_class}: #{failure.error_message})"
            end
          end

          def read_choice(input)
            line = input.gets
            return nil if line.nil?

            line.to_s.strip
          rescue IOError
            raise
          end

          def normalize_group_value(value)
            value.to_s.strip.downcase.tr('-', '_').to_sym
          end

          def count_for_group(counts, group)
            value = counts[group]
            return value.to_i if value

            0
          end

          def build_log_config(options)
            output, log_file = logger_output(options)
            register_log_file_closer(log_file)

            {
              level: logger_level(options),
              output: output,
              profile_path: resolve_profile_path(options),
              debug: debug_enabled?(options),
            }
          end

          def resolve_profile_path(options)
            path = (options[:profile_path] || env_profile_path).to_s.strip
            path.empty? ? nil : path
          end

          def logger_output(options)
            return [$stdout, nil] if debug_enabled?(options)

            path = (options[:log_path] || env_log_path).to_s.strip
            return [IO::NULL, nil] if path.empty?

            ensure_log_directory(path)
            file = File.open(path, 'a')
            file.sync = true
            [file, file]
          rescue IOError, SystemCallError, ArgumentError
            [IO::NULL, nil]
          end

          def ensure_log_directory(path)
            require 'fileutils'
            FileUtils.mkdir_p(File.dirname(path))
          end

          def logger_level(options)
            return :debug if debug_enabled?(options)

            configured_level = options[:log_level] || env_log_level
            normalize_log_level(configured_level) || :error
          end

          def normalize_log_level(level)
            value = level.to_s.strip.downcase
            return nil if value.empty?

            %w[debug info warn error fatal].include?(value) ? value.to_sym : nil
          end

          def debug_enabled?(options)
            return true if options[:debug]

            value = ENV.fetch('DEBUG', '').to_s.strip.downcase
            return false if value.empty?

            !%w[0 false off no].include?(value)
          end

          def env_log_path
            ENV.fetch('SHOKO_LOG_PATH', '').to_s.strip
          end

          def env_log_level
            ENV.fetch('SHOKO_LOG_LEVEL', '').to_s.strip
          end

          def env_profile_path
            ENV.fetch('SHOKO_PROFILE_PATH', '').to_s.strip
          end

          def register_log_file_closer(log_file)
            return unless log_file

            at_exit { close_log_file(log_file) }
          end

          def close_log_file(log_file)
            return if log_file.closed?

            log_file.close
          rescue IOError, SystemCallError => e
            Kernel.warn("[shoko] Failed to close log file: #{e.class}: #{e.message}")
          end
        end
      end
    end
  end
end
