# frozen_string_literal: true

require 'set'
require 'spec_helper'

RSpec.describe 'Hexagonal hardening guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:application_root) { File.join(lib_root, 'application') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  it 'forbids deprecated UI-shaped core menu ports in application layer' do
    files = Dir[File.join(application_root, '**', '*.rb')]
    patterns = {
      'menu_navigation_reader port' => /core\/ports\/outbound\/menu_navigation_reader|\bMenuNavigationReader\b/,
      'menu_query_reader port' => /core\/ports\/outbound\/menu_query_reader|\bMenuQueryReader\b/,
      'menu_data_reader port' => /core\/ports\/outbound\/menu_data_reader|\bMenuDataReader\b/,
      'menu_state_writer port' => /core\/ports\/outbound\/menu_state_writer|\bCore::Ports::Outbound::MenuStateWriter\b/,
      'reader_overlay_state_reader port' => /core\/ports\/outbound\/reader_overlay_state_reader|\bReaderOverlayStateReader\b/
    }

    offenders = files.flat_map do |path|
      content = non_comment_content(path)
      patterns.filter_map do |label, pattern|
        next unless content.match?(pattern)

        "#{rel(path)}: #{label}"
      end
    end

    expect(offenders).to eq([]), "Application depends on deprecated UI-shaped ports:\n#{offenders.join("\n")}"
  end

  it 'forbids private helper dispatch via menu.send in bootstrap menu composition' do
    path = File.join(lib_root, 'bootstrap', 'container_factory', 'controller_composition', 'menu_builder.rb')
    content = non_comment_content(path)

    expect(content).not_to include('menu.send('),
                          'Bootstrap menu composition must call explicit public menu APIs (menu.send found).'
  end

  it 'forbids respond_to? capability checks in application command use-cases' do
    files = Dir[File.join(application_root, 'use_cases', 'commands', '*.rb')]
    pattern = /\bcontext\.respond_to\?\(/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "Application commands must use typed command contexts instead of respond_to?:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end

  it 'forbids respond_to? collaborator validation in ReaderLaunchService dependencies' do
    path = File.join(application_root, 'workflows', 'menu', 'reader_launch_service.rb')
    content = non_comment_content(path)

    expect(content).not_to match(/\brespond_to\?\(/),
                          'ReaderLaunchService dependency validation must use typed contracts, not respond_to?.'
  end

  it 'keeps state store orchestration free from direct JSON/file persistence logic' do
    path = File.join(lib_root, 'adapters', 'runtime', 'session_state', 'state_store.rb')
    content = non_comment_content(path)
    forbidden = {
      'JSON.parse' => /JSON\.parse/,
      'JSON.pretty_generate' => /JSON\.pretty_generate/,
      'config_storage.read_file' => /\.read_file\(/,
      'config_storage.atomic_write' => /\.atomic_write\(/,
    }

    offenders = forbidden.filter_map { |label, pattern| label if content.match?(pattern) }

    expect(offenders).to eq([]),
                         "StateStore must delegate persistence/parsing to collaborators (found: #{offenders.join(', ')})"
  end

  it 'forbids initialize(**deps) constructors in menu controllers and workflows' do
    files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', '**', '*.rb')] +
            Dir[File.join(lib_root, 'application', 'workflows', '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(/def initialize\s*\([^)]*\*\*deps/) }

    expect(offenders).to eq([]), "Typed dependency objects are required; found **deps constructors:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end

  it 'forbids direct File/Process usage in application layer' do
    files = Dir[File.join(application_root, '**', '*.rb')]
    patterns = {
      'File usage' => /\bFile\./,
      'Process usage' => /\bProcess\./,
    }

    offenders = files.flat_map do |path|
      content = non_comment_content(path)
      patterns.filter_map do |label, pattern|
        next unless content.match?(pattern)

        "#{rel(path)}: #{label}"
      end
    end

    expect(offenders).to eq([]), "Application layer must use ports for infra access:\n#{offenders.join("\n")}"
  end

  it 'requires explicit resilient-boundary annotation for broad rescues in hardening scope' do
    files = Dir[File.join(lib_root, 'application', 'workflows', '**', '*.rb')] +
            Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', '**', '*.rb')] +
            Dir[File.join(lib_root, 'adapters', 'runtime', 'session_state', '**', '*.rb')]

    offenders = []
    files.each do |path|
      lines = File.readlines(path)
      lines.each_with_index do |line, index|
        next unless line.match?(/\brescue StandardError\b/)

        prev = index.positive? ? lines[index - 1] : ''
        next if prev.include?('# resilient-boundary')

        offenders << "#{rel(path)}:#{index + 1}"
      end
    end

    expect(offenders).to eq([]),
                         "Broad rescues in hardening scope require '# resilient-boundary':\n#{offenders.join("\n")}"
  end

  it 'contains hardcoded keyword highlighting to approved rendering files only' do
    allowed = Set.new([
                        File.join(lib_root, 'adapters', 'ui', 'constants', 'highlighting.rb'),
                        File.join(lib_root, 'adapters', 'ui', 'rendering', 'line', 'line_content_composer.rb'),
                        File.join(lib_root, 'adapters', 'ui', 'rendering', 'line', 'inline_segment_highlighter.rb')
                      ])
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /Constants::Highlighting::(?:HIGHLIGHT_WORDS|HIGHLIGHT_PATTERNS|QUOTE_PATTERNS)/

    offenders = files.select do |path|
      next false if allowed.include?(path)

      non_comment_content(path).match?(pattern)
    end

    expect(offenders).to eq([]),
                         "Hardcoded highlighting constants leaked outside approved files:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end

  it 'forbids Rouge references in runtime source until highlighting port decision is approved' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(/\brouge\b/i) }

    expect(offenders).to eq([]),
                         "Rouge references are deferred by architecture decision:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end
end
