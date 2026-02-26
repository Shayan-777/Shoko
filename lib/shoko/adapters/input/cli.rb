# frozen_string_literal: true

require 'optparse'
require_relative '../../shared/version'

# Root namespace for the Shoko application.
module Shoko
  module Adapters
    module Input
      # Command-line entry adapter that parses argv and launches the application.
      class CLI
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
          rescue StandardError
            false
          end

          def run_directory_import_session(directory_path, log_config:, folder_import_factory:, input:, output:)
            context = folder_import_factory.call(log_config: log_config)
            workflow = read_object_field(context, :workflow)
            raise ArgumentError, 'folder import workflow is required' unless workflow&.respond_to?(:discover)
            raise ArgumentError, 'folder import workflow must implement #import' unless workflow.respond_to?(:import)

            report = workflow.discover(directory_path, recursive: true, skip_hidden: true)
            print_discovery_report(report, output)

            if report_total_count(report).zero?
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

            import_report = execute_import(
              workflow: workflow,
              documents: documents,
              context: context,
              output: output
            )
            print_import_summary(import_report, output)
            :menu
          rescue StandardError => e
            output.puts
            output.puts "Directory import failed: #{e.class}: #{e.message}"
            :menu
          end

          def print_discovery_report(report, output)
            output.puts
            output.puts "Directory: #{report_directory_path(report)}"
            output.puts "Identified Documents: #{report_total_count(report)}"

            counts = report_counts(report)
            FORMAT_GROUP_ORDER.each do |group|
              count = count_for_group(counts, group)
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
            documents = report_documents(report)
            return documents if action == :all

            group = prompt_format_group_selection(report, input, output)
            return [] unless group

            documents.select do |document|
              normalize_group_value(read_object_field(document, :format_group)) == group
            end
          end

          def prompt_format_group_selection(report, input, output)
            groups = available_format_groups(report)
            return nil if groups.empty?

            loop do
              output.puts
              output.puts 'Choose a file type:'
              groups.each_with_index do |group, index|
                label = FORMAT_GROUP_LABELS.fetch(group, group.to_s.upcase)
                count = count_for_group(report_counts(report), group)
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
            counts = report_counts(report)
            FORMAT_GROUP_ORDER.select { |group| count_for_group(counts, group).positive? }
          end

          def execute_import(workflow:, documents:, context:, output:)
            presenter = build_progress_presenter(context)
            presenter&.start(message: "Importing #{documents.length} document(s)...")

            workflow.import(documents) do |done:, total:, path:, status:|
              progress = total.to_i.positive? ? done.to_f / total.to_f : 1.0
              message = "Importing (#{done}/#{total}) #{File.basename(path.to_s)} [#{status}]"
              presenter&.update_status(message: message, progress: progress)
            end
          ensure
            presenter&.finish
            output.flush if output.respond_to?(:flush)
          end

          def build_progress_presenter(context)
            factory = read_object_field(context, :progress_presenter_factory)
            return nil unless factory&.respond_to?(:call)

            factory.call
          rescue StandardError
            nil
          end

          def print_import_summary(report, output)
            output.puts
            output.puts format('Import completed in %.2fs', import_elapsed_seconds(report))
            output.puts "- Selected: #{import_total_count(report)}"
            output.puts "- Imported: #{import_imported_count(report)}"
            output.puts "- Skipped (cached): #{import_skipped_count(report)}"
            output.puts "- Failed: #{import_failed_count(report)}"

            failures = import_failures(report)
            return if failures.empty?

            output.puts "Failures (showing up to #{MAX_FAILURE_LINES}):"
            failures.first(MAX_FAILURE_LINES).each_with_index do |failure, index|
              path = read_object_field(failure, :path).to_s
              error_class = read_object_field(failure, :error_class).to_s
              message = read_object_field(failure, :error_message).to_s
              output.puts "#{index + 1}) #{path} (#{error_class}: #{message})"
            end
          end

          def read_choice(input)
            line = input.gets
            return nil if line.nil?

            line.to_s.strip
          rescue StandardError
            nil
          end

          def read_object_field(object, field, default = nil)
            return default if object.nil?
            return object.public_send(field) if object.respond_to?(field)

            if object.is_a?(Hash)
              return object[field] if object.key?(field)
              return object[field.to_s] if object.key?(field.to_s)
            end

            default
          rescue StandardError
            default
          end

          def normalize_group_value(value)
            value.to_s.strip.downcase.tr('-', '_').to_sym
          end

          def report_directory_path(report)
            read_object_field(report, :directory_path, '')
          end

          def report_documents(report)
            Array(read_object_field(report, :documents, []))
          end

          def report_counts(report)
            read_object_field(report, :counts_by_group, {}) || {}
          end

          def report_total_count(report)
            read_object_field(report, :total_count, report_documents(report).length).to_i
          end

          def count_for_group(counts, group)
            return 0 unless counts.is_a?(Hash)

            raw = counts[group]
            raw = counts[group.to_s] if raw.nil?
            raw.to_i
          end

          def import_total_count(report)
            read_object_field(report, :total_count, 0).to_i
          end

          def import_imported_count(report)
            read_object_field(report, :imported_count, 0).to_i
          end

          def import_skipped_count(report)
            read_object_field(report, :skipped_count, 0).to_i
          end

          def import_failed_count(report)
            read_object_field(report, :failed_count, 0).to_i
          end

          def import_failures(report)
            Array(read_object_field(report, :failures, []))
          end

          def import_elapsed_seconds(report)
            read_object_field(report, :elapsed_seconds, 0.0).to_f
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
          rescue StandardError
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
          rescue StandardError => e
            Kernel.warn("[shoko] Failed to close log file: #{e.class}: #{e.message}")
          end
        end
      end
    end
  end

  # Backward-compatible top-level alias for existing entry scripts.
  CLI = Adapters::Input::CLI unless const_defined?(:CLI)
end
