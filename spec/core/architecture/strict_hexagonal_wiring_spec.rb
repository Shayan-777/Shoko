# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Strict hexagonal wiring boundaries' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def relative(path)
    path.delete_prefix("#{lib_root}/")
  end

  def non_comment_lines(path)
    File.readlines(path).each_with_index.filter_map do |line, index|
      next if line.strip.start_with?('#')

      [index + 1, line]
    end
  rescue StandardError
    []
  end

  def require_relative_targets(path)
    File.readlines(path).each_with_index.filter_map do |line, index|
      match = line.match(/^\s*require_relative\s+['"]([^'"]+)['"]/)
      next unless match

      raw = match[1]
      target = raw.end_with?('.rb') ? raw : "#{raw}.rb"
      expanded = File.expand_path(target, File.dirname(path))
      next unless expanded.start_with?(lib_root)

      [index + 1, relative(expanded)]
    end
  rescue StandardError
    []
  end

  it 'forbids adapters from requiring application files' do
    files = Dir[File.join(lib_root, 'adapters', '**', '*.rb')]
    allowed_targets = {
      'adapters/input/controllers/reader_controller.rb' => ['application/services/document_path_resolver.rb']
    }
    offenders = []

    files.each do |path|
      source = relative(path)
      require_relative_targets(path).each do |line, target|
        next unless target.start_with?('application/')
        next if allowed_targets.fetch(source, []).include?(target)

        offenders << "#{source}:#{line} -> #{target}"
      end
    end

    expect(offenders).to be_empty,
                             "Adapters require application files directly:\n#{offenders.sort.join("\n")}"
  end

  it 'forbids adapters from referencing application constants' do
    files = Dir[File.join(lib_root, 'adapters', '**', '*.rb')]
    pattern = /\b(?:Shoko::)?Application::/
    allowed_patterns = {
      'adapters/input/controllers/reader_controller.rb' => /\b(?:Shoko::)?Application::Services::DocumentPathResolver\b/
    }
    offenders = []

    files.each do |path|
      source = relative(path)
      non_comment_lines(path).each do |line_no, line|
        next unless line.match?(pattern)
        allowed = allowed_patterns[source]
        next if allowed && line.match?(allowed)

        offenders << "#{source}:#{line_no}: #{line.strip}"
      end
    end

    expect(offenders).to be_empty,
                             "Adapters reference application constants directly:\n#{offenders.sort.join("\n")}"
  end
end
