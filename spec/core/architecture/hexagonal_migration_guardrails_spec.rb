# frozen_string_literal: true

require 'ripper'
require 'spec_helper'

RSpec.describe 'Hexagonal migration guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:application_root) { File.join(lib_root, 'application') }

  SESSION_REQUIRED_KEYWORDS = %w[
    doc
    page_calculator
    app_config_store
    reader_session_store
  ].freeze

  SESSION_LEGACY_KEYWORDS = %w[
    config_reader
    reader_state_reader
    pagination_state_writer
    ui_loading_writer
    sidebar_state_reader
    state_writer
  ].freeze

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  def walk(node, &block)
    return unless node.is_a?(Array)

    block.call(node)
    node.each { |child| walk(child, &block) if child.is_a?(Array) }
  end

  def call_line(call_node)
    ident = call_node[3]
    return 1 unless ident.is_a?(Array) && ident[2].is_a?(Array)

    ident[2][0]
  end

  def session_call_node?(node)
    return false unless node.is_a?(Array) && node[0] == :call

    ident = node[3]
    ident.is_a?(Array) && ident[0] == :@ident && ident[1] == 'session'
  end

  def receiver_contains_orchestrator?(receiver_node)
    return false unless receiver_node.is_a?(Array)

    matches = []
    walk(receiver_node) do |node|
      next unless node.is_a?(Array)
      next unless %i[@ident @ivar].include?(node[0])

      matches << node[1].to_s
    end
    matches.any? { |name| name.include?('orchestrator') }
  end

  def keyword_labels(args_node)
    labels = []
    walk(args_node) do |node|
      next unless node.is_a?(Array) && node[0] == :@label

      labels << node[1].to_s.sub(/:\z/, '')
    end
    labels.uniq
  end

  def pagination_session_call_offenders(path)
    ast = Ripper.sexp(File.read(path))
    return [] unless ast

    offenders = []
    walk(ast) do |node|
      next unless node.is_a?(Array) && node[0] == :method_add_arg

      call_node = node[1]
      next unless session_call_node?(call_node)
      next unless receiver_contains_orchestrator?(call_node[1])

      labels = keyword_labels(node[2])
      missing = SESSION_REQUIRED_KEYWORDS - labels
      legacy = labels & SESSION_LEGACY_KEYWORDS
      next if missing.empty? && legacy.empty?

      details = []
      details << "missing=#{missing.join(',')}" unless missing.empty?
      details << "legacy=#{legacy.join(',')}" unless legacy.empty?
      offenders << "#{rel(path)}:#{call_line(call_node)} #{details.join(' ')}"
    end

    offenders
  rescue StandardError => e
    ["#{rel(path)}:parse_error #{e.class}: #{e.message}"]
  end

  it 'requires session store pagination keywords in application orchestrator callsites (AST)' do
    files = Dir[File.join(application_root, '**', '*.rb')]
    offenders = files.flat_map { |path| pagination_session_call_offenders(path) }

    expect(offenders).to eq([]),
                         "PaginationOrchestrator#session callsites must use session-store keyword contract:\n#{offenders.join("\n")}"
  end

  it 'forbids callback-style pagination rendering hooks in application layer' do
    files = Dir[File.join(application_root, '**', '*.rb')]
    patterns = {
      'render_callback reference' => /\brender_callback\b/,
      'direct controller redraw call' => /\b(?:@?\w*controller)\.(?:force_redraw|draw_screen)\b/,
      'direct force_redraw call' => /\bforce_redraw\b/,
    }

    offenders = files.flat_map do |path|
      content = non_comment_content(path)
      patterns.filter_map do |label, pattern|
        next unless content.match?(pattern)

        "#{rel(path)}: #{label}"
      end
    end

    expect(offenders).to eq([]),
                         "Application layer must render through outbound ports, not callbacks/controller redraws:\n#{offenders.join("\n")}"
  end

  it 'forbids reflection-style collaborator probing in CLI workflows' do
    files = Dir[File.join(application_root, 'workflows', 'cli', '**', '*.rb')]
    pattern = /\brespond_to\?\(|\bpublic_send\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "CLI workflows must use typed collaborators, not reflection probing:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end

  it 'forbids backend-specific error-string diagnosis in core dictionary service' do
    path = File.join(lib_root, 'core', 'services', 'dictionary_service.rb')
    content = non_comment_content(path)
    forbidden = [
      /database disk image is malformed/i,
      /file is not a database/i,
      /no such table/i,
      /sqlite/i,
      /permission denied/i
    ]

    offenders = forbidden.select { |pattern| content.match?(pattern) }
    expect(offenders).to eq([]),
                         'Core dictionary service must not parse backend-specific error strings.'
  end

  it 'forbids reflection-based dispatch and collaborator probing in strict migration scope' do
    strict_roots = [
      File.join(lib_root, 'core'),
      File.join(lib_root, 'application'),
      File.join(lib_root, 'adapters', 'runtime'),
      File.join(lib_root, 'composition')
    ]
    files = strict_roots.flat_map { |root_path| Dir[File.join(root_path, '**', '*.rb')] }
    pattern = /\brespond_to\?\(|\bpublic_send\b|\bsend\s*\(/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "Strict migration scope must not use reflection probing/dispatch:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end

  it 'forbids synthetic error-document fallbacks in book loading pipeline' do
    files = [
      File.join(lib_root, 'adapters', 'book_sources', 'document_service.rb'),
      File.join(lib_root, 'adapters', 'book_sources', 'book_document.rb')
    ]
    patterns = [
      /\bErrorDocument\b/,
      /\bErrorChapter\b/,
      /create_error_document/,
      /create_error_chapter/
    ]
    offenders = files.flat_map do |path|
      content = non_comment_content(path)
      patterns.filter_map do |pattern|
        next unless content.match?(pattern)

        "#{rel(path)}: #{pattern.inspect}"
      end
    end

    expect(offenders).to eq([]),
                         "Legacy synthetic error-document fallbacks must remain removed:\n#{offenders.join("\n")}"
  end

  it 'enforces broad-rescue policy in hardening scope (strict core/app + allowlisted boundaries only)' do
    hardening_scope = [
      File.join(lib_root, 'application', 'pending_jump_handler.rb'),
      File.join(lib_root, 'application', 'services', 'pagination', 'pagination_coordinator.rb'),
      File.join(lib_root, 'application', 'use_cases', 'settings_service.rb'),
      File.join(lib_root, 'application', 'workflows', 'cli', 'folder_import_workflow.rb'),
      File.join(lib_root, 'core', 'services', 'dictionary_service.rb')
    ]
    allowed_boundary_files = [
      rel(File.join(lib_root, 'application', 'services', 'pagination', 'pagination_coordinator.rb')),
      rel(File.join(lib_root, 'application', 'workflows', 'cli', 'folder_import_workflow.rb'))
    ].freeze

    offenders = []
    hardening_scope.each do |path|
      lines = File.readlines(path)
      lines.each_with_index do |line, index|
        next unless line.match?(/\brescue StandardError\b/)

        relative = rel(path)
        line_number = index + 1
        unless allowed_boundary_files.include?(relative)
          offenders << "#{relative}:#{line_number} (file not allowlisted)"
          next
        end

        previous = index.positive? ? lines[index - 1] : ''
        next if previous.include?('# resilient-boundary')

        offenders << "#{relative}:#{line_number} (missing # resilient-boundary)"
      end
    end

    expect(offenders).to eq([]),
                         "Broad rescue policy violated in hardening scope:\n#{offenders.join("\n")}"
  end

  it 'forbids untyped collaborator validation patterns in workflow constructors' do
    files = Dir[File.join(application_root, 'workflows', '**', '*.rb')]
    offenders = []

    files.each do |path|
      lines = File.readlines(path)
      in_initialize = false
      depth = 0

      lines.each_with_index do |line, index|
        stripped = line.strip
        if stripped.start_with?('def initialize')
          in_initialize = true
          depth = 1
          next
        end

        next unless in_initialize

        depth += 1 if stripped.start_with?('def ')
        if stripped == 'end'
          depth -= 1
          if depth.zero?
            in_initialize = false
          end
          next
        end

        next unless stripped.match?(/\brespond_to\?\(|\bpublic_send\b/)

        offenders << "#{rel(path)}:#{index + 1}"
      end
    end

    expect(offenders).to eq([]),
                         "Workflow constructors must use typed contract checks (no respond_to?/public_send):\n#{offenders.join("\n")}"
  end
end
