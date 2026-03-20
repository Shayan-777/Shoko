# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      class CLI
        # Directory import orchestration and CLI-facing coercion helpers.
        module DirectoryImportSupport
          private

          def run_directory_import_session(directory_path, log_config:, folder_import_factory:, input:, output:)
            workflow, context, report = prepare_import(directory_path, log_config, folder_import_factory, output)
            return no_supported_documents(output) if report.total_count.zero?

            import_selection = import_selection_for(report, input, output)
            resolve_import_selection(workflow, context, import_selection, output)
          rescue ArgumentError, TypeError => e
            raise Shoko::FatalExternalInputError.new(
              "directory import malformed input: #{e.message}",
              source: :directory_import
            )
          rescue IOError, SystemCallError => e
            raise Shoko::FatalExternalInputError, "directory import I/O failure: #{e.class}: #{e.message}"
          end

          def prepare_import(directory_path, log_config, folder_import_factory, output)
            context = coerce_folder_import_context(folder_import_factory.call(log_config: log_config))
            workflow = context.workflow
            report = coerce_discovery_report(workflow.discover(directory_path, recursive: true, skip_hidden: true))
            print_discovery_report(report, output)
            [workflow, context, report]
          end

          def no_supported_documents(output)
            output.puts
            output.puts 'No supported documents were found. Opening menu...'
            :menu
          end

          def no_selected_documents(output)
            output.puts
            output.puts 'No documents selected for import. Opening menu...'
            :menu
          end

          def import_selection_for(report, input, output)
            action = prompt_import_action(input, output)
            return :exit if action == :exit

            documents = select_documents_for_import(report, action, input, output)
            return no_selected_documents(output) if documents.empty?

            documents
          end

          def finalize_import_session(workflow, context, documents, output)
            import_report = coerce_import_report(
              execute_import(workflow: workflow, documents: documents, context: context, output: output)
            )
            print_import_summary(import_report, output)
            :menu
          end

          def resolve_import_selection(workflow, context, import_selection, output)
            return import_selection if import_selection.is_a?(Symbol)

            finalize_import_session(workflow, context, import_selection, output)
          end

          def print_discovery_report(report, output)
            output.puts
            output.puts "Directory: #{report.directory_path}"
            output.puts "Identified Documents: #{report.total_count}"
            discovery_report_lines(report).each { |line| output.puts(line) }
          end

          def discovery_report_lines(report)
            FORMAT_GROUP_ORDER.filter_map do |group|
              count = count_for_group(report.counts_by_group, group)
              next unless count.positive?

              label = FORMAT_GROUP_LABELS.fetch(group, group.to_s.upcase)
              noun = count == 1 ? 'file' : 'files'
              "- #{count} #{label} #{noun}"
            end
          end

          def prompt_import_action(input, output)
            loop do
              print_import_actions(output)

              choice = read_choice(input)
              return :exit if choice.nil?
              return :all if choice == '1'
              return :single_type if choice == '2'
              return :exit if choice == '3'

              output.puts 'Invalid choice. Enter 1, 2, or 3.'
            end
          end

          def print_import_actions(output)
            output.puts
            output.puts 'Action:'
            output.puts '1) Import all documents'
            output.puts '2) Import only one file type'
            output.puts '3) Exit'
            output.print 'Answer: '
          end

          def select_documents_for_import(report, action, input, output)
            return report.documents if action == :all

            group = prompt_format_group_selection(report, input, output)
            return [] unless group

            report.documents.select { |document| document.format_group == group }
          end

          def prompt_format_group_selection(report, input, output)
            groups = available_format_groups(report)
            return nil if groups.empty?

            loop do
              print_format_group_prompt(groups, report, output)

              selection = parse_format_group_choice(read_choice(input), groups.length)
              return nil if selection == :cancel
              return groups[selection - 1] if selection.is_a?(Integer)

              output.puts "Invalid choice. Enter a number between 1 and #{groups.length + 1}."
            end
          end

          def print_format_group_prompt(groups, report, output)
            output.puts
            output.puts 'Choose a file type:'
            groups.each_with_index do |group, index|
              label = FORMAT_GROUP_LABELS.fetch(group, group.to_s.upcase)
              count = count_for_group(report.counts_by_group, group)
              output.puts "#{index + 1}) #{label} (#{count})"
            end
            output.puts "#{groups.length + 1}) Cancel"
            output.print 'Answer: '
          end

          def parse_format_group_choice(choice, group_count)
            return :cancel if choice.nil?

            selected = choice.to_i
            return selected if selected.between?(1, group_count)
            return :cancel if selected == group_count + 1

            :invalid
          end

          def available_format_groups(report)
            FORMAT_GROUP_ORDER.select { |group| count_for_group(report.counts_by_group, group).positive? }
          end

          def execute_import(workflow:, documents:, context:, output:)
            presenter = build_progress_presenter(context)
            presenter&.start(message: "Importing #{documents.length} document(s)...")

            workflow.import(documents) do |done:, total:, path:, status:, message: nil, progress: nil|
              presenter&.update_status(
                message: message || default_import_message(done: done, total: total, path: path, status: status),
                progress: progress || default_import_progress(done: done, total: total)
              )
            end
          ensure
            presenter&.finish
            output.flush
          end

          def build_progress_presenter(context)
            factory = context.progress_presenter_factory
            factory&.call
          end

          def print_import_summary(report, output)
            summary_lines(report).each { |line| output.puts(line) }
          end

          def summary_lines(report)
            lines = [
              '',
              format('Import completed in %.2fs', report.elapsed_seconds),
              "- Selected: #{report.total_count}",
              "- Imported: #{report.imported_count}",
              "- Skipped (cached): #{report.skipped_count}",
              "- Failed: #{report.failed_count}",
            ]
            lines.concat(failure_lines(report))
          end

          def failure_lines(report)
            failures = report.failures
            return [] if failures.empty?

            [
              "Failures (showing up to #{MAX_FAILURE_LINES}):",
              *failures.first(MAX_FAILURE_LINES).each_with_index.map do |failure, index|
                "#{index + 1}) #{failure.path} (#{failure.error_class}: #{failure.error_message})"
              end,
            ]
          end

          def read_choice(input)
            line = input.gets
            line&.to_s&.strip
          end

          def normalize_group_value(value)
            value.to_s.strip.downcase.tr('-', '_').to_sym
          end

          def count_for_group(counts, group)
            value = counts[group]
            value ? value.to_i : 0
          end

          def default_import_message(done:, total:, path:, status:)
            basename = File.basename(path.to_s)
            return "Importing #{basename}..." if status == :running

            "Importing (#{done}/#{total}) #{basename} [#{status}]"
          end

          def default_import_progress(done:, total:)
            return 1.0 unless total.to_i.positive?

            done.to_f / total
          end
        end
      end
    end
  end
end
