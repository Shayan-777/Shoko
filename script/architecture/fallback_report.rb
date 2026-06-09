#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

require_relative '../../spec/support/architecture/rescue_guardrail_analyzer'

ROOT = File.expand_path('../..', __dir__)
LIB_ROOT = File.join(ROOT, 'lib', 'shoko')
APPLICATION_ROOT = File.join(LIB_ROOT, 'application')

def rel(path)
  path.delete_prefix("#{ROOT}/")
end

def mixed_key_read_offenders
  patterns = [
    /\b([a-z_]\w*)\[:([a-z_]\w*)\]\s*\|\|\s*\1\[['"]\2['"]\]/i,
    /\b([a-z_]\w*)\[['"]([a-z_]\w*)['"]\]\s*\|\|\s*\1\[:\2\]/i
  ]

  Dir[File.join(APPLICATION_ROOT, '**', '*.rb')].flat_map do |path|
    File.readlines(path).each_with_index.filter_map do |line, index|
      next if line.strip.start_with?('#')
      next unless patterns.any? { |pattern| line.match?(pattern) }

      "#{rel(path)}:#{index + 1}"
    end
  end.sort
end

def fatal_swallow_offenders
  rescue_body_lines = lambda do |lines, rescue_index|
    rescue_indent = lines[rescue_index][/^\s*/].size
    index = rescue_index + 1
    body = []

    while index < lines.length
      line = lines[index]
      stripped = line.strip
      indent = line[/^\s*/].size
      break if indent <= rescue_indent && stripped.match?(/^(rescue|ensure|end)\b/)

      body << stripped unless stripped.empty? || stripped.start_with?('#')
      index += 1
    end

    body
  end

  terminating_body = lambda do |body_lines|
    body_lines.any? do |line|
      line.start_with?('raise') || line.include?('terminate(2)') || line.include?('cleanup_and_exit(2')
    end
  end

  files = [
    File.join(LIB_ROOT, 'adapters', 'input', 'cli.rb'),
    File.join(LIB_ROOT, 'adapters', 'input', 'controllers', 'menu', 'controller.rb'),
    File.join(LIB_ROOT, 'adapters', 'input', 'controllers', 'reader', 'lifecycle_runner.rb'),
    File.join(LIB_ROOT, 'application', 'unified_application.rb'),
    File.join(LIB_ROOT, 'application', 'workflows', 'menu', 'download_workflow.rb'),
    File.join(LIB_ROOT, 'application', 'workflows', 'menu', 'dictionary_workflow.rb')
  ]

  files.flat_map do |path|
    lines = File.readlines(path)
    lines.each_with_index.filter_map do |line, index|
      next unless line.match?(/^\s*rescue\s+Shoko::FatalExternalInputError/)

      body = rescue_body_lines.call(lines, index)
      next if terminating_body.call(body)

      "#{rel(path)}:#{index + 1}"
    end
  end.sort
end

analyzer = SpecSupport::Architecture::RescueGuardrailAnalyzer

# Adapter-layer files where rescuing into a literal is the documented port
# contract (IO/parse exceptions translate into typed values). Kept in sync
# with EXEMPT_FILES in spec/core/architecture/no_rescue_literal_default_spec.rb.
FALLBACK_LITERAL_EXEMPT_FILES = [
  'adapters/book_sources/book_finder.rb',
  'adapters/book_sources/epub/parser/opf/navigation_document_scanner.rb',
  'adapters/storage/repositories/display_metadata_cache_repository.rb',
  'adapters/storage/file_probe_adapter.rb'
].freeze

def reject_exempt(offenders, exempt_files)
  offenders.reject do |entry|
    exempt_files.any? { |exempt| entry.start_with?("#{exempt}:") }
  end
end

report = {
  fallback_literal_defaults: reject_exempt(
    analyzer.fallback_literal_rescue_offenders(lib_root: LIB_ROOT),
    FALLBACK_LITERAL_EXEMPT_FILES
  ).sort,
  numeric_rescue_defaults: analyzer.numeric_default_rescue_offenders(lib_root: LIB_ROOT).sort,
  no_op_reraise_rescues: analyzer.no_op_reraise_rescue_offenders(lib_root: LIB_ROOT).sort,
  fatal_input_swallow_rescues: fatal_swallow_offenders,
  mixed_key_reads_application: mixed_key_read_offenders
}

report[:summary] = {
  fallback_literal_defaults: report[:fallback_literal_defaults].length,
  numeric_rescue_defaults: report[:numeric_rescue_defaults].length,
  no_op_reraise_rescues: report[:no_op_reraise_rescues].length,
  fatal_input_swallow_rescues: report[:fatal_input_swallow_rescues].length,
  mixed_key_reads_application: report[:mixed_key_reads_application].length
}

puts JSON.pretty_generate(report)

has_offenders = report[:summary].values.any?(&:positive?)
exit(has_offenders ? 1 : 0)
