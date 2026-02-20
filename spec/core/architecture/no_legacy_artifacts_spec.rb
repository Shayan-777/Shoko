# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No legacy runtime artifacts' do
  let(:root) { File.expand_path('../../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'forbids core references to application ports' do
    files = Dir[File.join(lib_root, 'core', '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(/Application::Ports|application\/ports\//) }

    expect(offenders).to be_empty,
                         "Core references application ports:\n#{offenders.join("\n")}"
  end

  it 'forbids runtime config provider references' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).include?('RuntimeConfigProvider') }

    expect(offenders).to be_empty,
                         "RuntimeConfigProvider references remain:\n#{offenders.join("\n")}"
  end

  it 'forbids EnvRuntimeConfigAdapter construction outside bootstrap boundaries' do
    allowlist = [
      'bootstrap/container_factory/infrastructure_registration.rb',
      'bootstrap/container_factory/test_container_registration.rb',
      'adapters/runtime/env_runtime_config_adapter.rb'
    ]
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select do |path|
      next false unless non_comment_content(path).include?('EnvRuntimeConfigAdapter.new')

      !allowlist.any? { |allowed| path.end_with?(allowed) }
    end

    expect(offenders).to be_empty,
                         "EnvRuntimeConfigAdapter.new used outside allowed boundaries:\n#{offenders.join("\n")}"
  end

  it 'forbids internal runtime side-channel files' do
    internal_files = Dir[File.join(lib_root, 'internal', '**', '*')].reject { |path| File.directory?(path) }
    zip_shim = File.join(root, 'lib', 'zip.rb')
    offenders = internal_files
    offenders << zip_shim if File.exist?(zip_shim)

    expect(offenders).to be_empty,
                         "Internal/zip shim artifacts remain:\n#{offenders.join("\n")}"
  end

  it 'forbids runtime references to removed internal/zip shim entrypoints' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = %r{shoko/internal|require_relative\s+['"][^'"]*internal/|require\s+['"]zip['"]}
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Runtime references removed internal/zip shim entrypoints:\n#{offenders.join("\n")}"
  end

  it 'forbids direct Zip::File coupling outside archive adapter' do
    allowlist = [File.join(lib_root, 'adapters', 'book_sources', 'archive', 'zip_reader.rb')]
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select do |path|
      next false unless non_comment_content(path).include?('Zip::File')

      !allowlist.include?(path)
    end

    expect(offenders).to be_empty,
                         "Direct Zip::File usage outside archive adapter:\n#{offenders.join("\n")}"
  end

  it 'forbids Core::Ports::CommandPort references' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).include?('Core::Ports::CommandPort') }

    expect(offenders).to be_empty,
                         "Core::Ports::CommandPort references remain:\n#{offenders.join("\n")}"
  end

  it 'forbids EPUBParseError and static logger references' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select do |path|
      content = non_comment_content(path)
      content.include?('EPUBParseError') || content.include?('Adapters::Monitoring::Logger')
    end

    expect(offenders).to be_empty,
                         "Legacy constants remain:\n#{offenders.join("\n")}"
  end

  it 'forbids empty application infrastructure placeholder directory' do
    path = File.join(lib_root, 'application', 'infrastructure')
    is_empty = Dir.exist?(path) && Dir.empty?(path)

    expect(is_empty).to eq(false), 'Remove empty lib/shoko/application/infrastructure directory'
  end

  it 'forbids legacy application dependency_container runtime path' do
    path = File.join(lib_root, 'application', 'dependency_container.rb')
    expect(File.exist?(path)).to eq(false), 'Remove lib/shoko/application/dependency_container.rb'
  end

  it 'forbids removed V3 runtime file paths from reappearing' do
    forbidden = %w[
      core/ports/progress_state_reader.rb
      adapters/runtime/session_state/progress_state_reader_adapter.rb
      application/main_menu/menu_progress_presenter.rb
      application/controllers/menu_controller.rb
      adapters/input/input_controller.rb
      adapters/runtime/session_state/command_port_adapter.rb
    ]
    offenders = forbidden.map { |relative| File.join(lib_root, relative) }.select { |path| File.exist?(path) }

    expect(offenders).to be_empty,
                         "Removed V3 files still exist:\n#{offenders.join("\n")}"
  end

  it 'forbids removed core-owned application port files from reappearing' do
    forbidden = %w[
      core/ports/config_reader.rb
      core/ports/reader_navigation_reader.rb
      core/ports/key_classifier.rb
      core/ports/notification_writer.rb
      core/ports/progress_state_reader.rb
    ]
    offenders = forbidden.map { |relative| File.join(lib_root, relative) }.select { |path| File.exist?(path) }

    expect(offenders).to be_empty,
                         "Removed core-owned application ports reappeared:\n#{offenders.join("\n")}"
  end

  it 'forbids legacy V3 path/namespace references across runtime/test sources and README' do
    files = Dir[File.join(root, '{lib,spec}', '**', '*.rb')] + [File.join(root, 'README.md')]
    files = files.reject { |path| path.end_with?('spec/core/architecture/no_legacy_artifacts_spec.rb') }
    pattern = /
      \bprogress_state_reader\b|
      application\/main_menu\/menu_progress_presenter|
      application\/controllers\/menu_controller|
      adapters\/state\/command_port_adapter|
      adapters\/input\/input_controller|
      Core::Ports::ProgressStateReader|
      Application::MainMenu
    /x
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Legacy V3 references remain:\n#{offenders.join("\n")}"
  end

  it 'forbids removed DI key registrations/resolutions for progress state reader' do
    files = Dir[File.join(root, '{lib,spec}', '**', '*.rb')]
    files = files.reject { |path| path.end_with?('spec/core/architecture/no_legacy_artifacts_spec.rb') }
    offenders = files.select { |path| non_comment_content(path).match?(/:progress_state_reader\b/) }

    expect(offenders).to be_empty,
                         "Deprecated :progress_state_reader DI key usage remains:\n#{offenders.join("\n")}"
  end

  it 'forbids V4-removed runtime directories from reappearing' do
    forbidden = [
      %w[application composition].join('/'),
      %w[adapters state].join('/'),
      %w[adapters output ui].join('/'),
      %w[adapters output rendering].join('/'),
      %w[application main_menu].join('/'),
    ]
    offenders = forbidden.map { |relative| File.join(lib_root, relative) }.select { |path| Dir.exist?(path) || File.exist?(path) }

    expect(offenders).to be_empty,
                         "V4-removed directories/files reappeared:\n#{offenders.join("\n")}"
  end

  it 'forbids V4-removed namespace/path references across lib/spec/README/docs' do
    files = Dir[File.join(root, '{lib,spec,docs}', '**', '*.{rb,md}')] + [File.join(root, 'README.md')]
    files = files.reject { |path| path.end_with?('spec/core/architecture/no_legacy_artifacts_spec.rb') }
    # Allow explicit historical migration notes in cleanup changelog.
    files = files.reject { |path| path.end_with?('docs/architecture/hexagonal_cleanup_changelog.md') }
    legacy_constants = [
      %w[Application Composition].join('::'),
      %w[Adapters State].join('::'),
      %w[Adapters Output Ui].join('::'),
      %w[Adapters Output Rendering].join('::'),
    ]
    legacy_paths = [
      %w[application composition].join('/'),
      %w[adapters state].join('/'),
      %w[adapters output ui].join('/'),
      %w[adapters output rendering].join('/'),
    ]
    pattern = Regexp.union(*(legacy_constants + legacy_paths))
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "V4-removed namespace/path references remain:\n#{offenders.join("\n")}"
  end

  it 'forbids global runtime-config setter hooks in runtime code' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /
      \b(?:TextMetrics|Tokenizer)\.runtime_config\s*=|
      \bTerminalBuffer::Frame\.install_runtime_config\b|
      def\s+(?:self\.)?runtime_config=|
      def\s+install_runtime_config\b
    /x
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Global runtime-config setter hooks remain:\n#{offenders.join("\n")}"
  end

  it 'forbids core services from invoking application writer-style mutations' do
    files = Dir[File.join(lib_root, 'core', 'services', '**', '*.rb')]
    writer_pattern = /
      \bupdate_reader\b|
      \bupdate_page\b|
      \bupdate_pagination_state\b|
      \bupdate_selections\b|
      \bupdate_navigation\b|
      \bupdate_config\b|
      \bupdate_sidebar\b|
      \bupdate_ui_loading\b|
      \bstate_writer\b
    /x
    offenders = files.select { |path| non_comment_content(path).match?(writer_pattern) }

    expect(offenders).to be_empty,
                         "Core services perform writer-style application mutations:\n#{offenders.join("\n")}"
  end
end
