# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Hexagonal coherence guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  it 'forbids legacy malformed-book string raises that bypass keyword initialization' do
    offenders = Dir[File.join(lib_root, '**', '*.rb')].filter_map do |path|
      next unless File.read(path).match?(/raise\s+Shoko::MalformedBookInputError\s*,/)

      rel(path)
    end

    expect(offenders).to eq([]),
                         "MalformedBookInputError must be constructed with keywords or replaced with a better type:\n#{offenders.join("\n")}"
  end

  it 'forbids non-UI runtime files from using UI theme normalization helpers' do
    offenders = Dir[File.join(lib_root, '**', '*.rb')].filter_map do |path|
      next if path.include?(File.join('adapters', 'ui'))

      content = File.read(path)
      next unless content.match?(/Themes\.(normalize_theme|valid_theme\?)/)

      rel(path)
    end

    expect(offenders).to eq([]),
                         "Theme identity policy must live outside UI constants:\n#{offenders.join("\n")}"
  end

  it 'locks the reviewed composition points to bootstrap-owned dependency injection' do
    expectations = {
      File.join(lib_root, 'adapters', 'input', 'cli.rb') => /ProcessControlAdapter\.new/,
      File.join(lib_root, 'adapters', 'book_sources', 'folder_scanner.rb') => /BookFileProbe\.new/,
      File.join(lib_root, 'adapters', 'book_sources', 'book_finder', 'directory_scanner.rb') => /BookFileProbe\.new/,
      File.join(lib_root, 'adapters', 'book_sources', 'metadata_reader_adapter.rb') => /Archive::ZipReader/,
      File.join(lib_root, 'adapters', 'storage', 'repositories', 'cached_library_repository.rb') => /JsonCacheStore\.new/,
    }

    offenders = expectations.filter_map do |path, pattern|
      next unless File.read(path).match?(pattern)

      rel(path)
    end

    expect(offenders).to eq([]),
                         "Reviewed composition points must not allocate sibling adapters outside bootstrap:\n#{offenders.join("\n")}"
  end

  it 'locks the document pipeline against the rewrapping regressions that caused duplicate malformed-input messages' do
    checks = {
      File.join(lib_root, 'adapters', 'book_sources', 'book_document.rb') => /BookParseError\.new\(e\.message, @open_path\)/,
      File.join(lib_root, 'adapters', 'book_sources', 'document_service.rb') => /BookParseError\.new\(e\.message, @book_path\)/,
      File.join(lib_root, 'adapters', 'book_sources', 'pdf', 'pdf_importer.rb') => /raise if e\.is_a\?\(Shoko::FileNotFoundError\)\s*$/,
    }

    offenders = checks.filter_map do |path, pattern|
      next unless File.read(path).match?(pattern)

      rel(path)
    end

    expect(offenders).to eq([]),
                         "File-scoped malformed input must propagate without being rewrapped in the document pipeline:\n#{offenders.join("\n")}"
  end
end
