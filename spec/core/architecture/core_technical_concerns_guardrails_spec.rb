# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Core technical concern guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'forbids parser trees from living under core' do
    core_parser_root = File.join(lib_root, 'core', 'book_formats')

    expect(File.exist?(core_parser_root)).to be(false),
      "Parser tree must not live under core: #{core_parser_root}"
  end

  it 'forbids default terminal/display implementations and document locator service in core services' do
    forbidden = %w[
      core/services/default_terminal_capabilities.rb
      core/services/default_display_capabilities.rb
      core/services/document_path_resolver.rb
    ].map { |rel| File.join(lib_root, rel) }
    offenders = forbidden.select { |path| File.exist?(path) }

    expect(offenders).to eq([]),
      "Core must not own runtime default implementations or document locator service:\n#{offenders.join("\n")}"
  end

  it 'forbids lib files from referencing removed core parser/runtime constants and paths' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    patterns = [
      /(?:Shoko::)?Core::BookFormats::/,
      /core\/book_formats\//,
      /(?:Shoko::)?Core::Services::DefaultTerminalCapabilities/,
      /(?:Shoko::)?Core::Services::DefaultDisplayCapabilities/,
      /(?:Shoko::)?Core::Services::DocumentPathResolver/
    ]
    offenders = files.filter_map do |path|
      content = non_comment_content(path)
      next unless patterns.any? { |pattern| content.match?(pattern) }

      path.delete_prefix("#{root}/")
    end

    expect(offenders).to eq([]),
      "Removed core technical concerns are still referenced:\n#{offenders.join("\n")}"
  end
end
