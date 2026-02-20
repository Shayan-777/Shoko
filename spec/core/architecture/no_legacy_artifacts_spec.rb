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

  it 'forbids EnvRuntimeConfigAdapter construction outside composition/bootstrap boundaries' do
    allowlist = [
      'application/composition/container_factory/infrastructure_registration.rb',
      'application/composition/container_factory/test_container_registration.rb',
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
end
