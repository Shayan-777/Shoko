# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No legacy runtime artifacts' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def const_name(*segments)
    segments.join('::')
  end

  def path_name(*segments)
    segments.join('/')
  end

  it 'forbids legacy architecture directories' do
    forbidden = [
      File.join(lib_root, *%w[application controllers]),
      File.join(lib_root, *%w[application ui]),
      File.join(lib_root, *%w[application dependencies]),
      File.join(lib_root, *%w[application ports]),
      File.join(lib_root, *%w[presentation ui])
    ]

    offenders = forbidden.select { |path| Dir.exist?(path) || File.exist?(path) }

    expect(offenders).to be_empty,
                         "Legacy architecture directories/files still exist:\n#{offenders.join("\n")}"
  end

  it 'forbids legacy namespace and path references across runtime/docs' do
    files = Dir[File.join(root, '{lib,spec,docs}', '**', '*.{rb,md}')] + [File.join(root, 'README.md')]
    files = files.reject { |path| path.include?(File.join('spec', 'core', 'architecture')) }

    legacy_constants = [
      const_name('Application', 'Controllers'),
      const_name('Presentation', 'Ui'),
      const_name('Application', 'Ui'),
      const_name('Application', 'Dependencies'),
      const_name('Application', 'Ports')
    ]
    legacy_paths = [
      path_name('application', 'controllers'),
      path_name('presentation', 'ui'),
      path_name('application', 'ui'),
      path_name('application', 'dependencies'),
      path_name('application', 'ports')
    ]

    pattern = Regexp.union(*(legacy_constants + legacy_paths))
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Legacy namespace/path references remain:\n#{offenders.join("\n")}"
  end

  it 'forbids removed command-port artifacts and references' do
    forbidden_files = [
      File.join(lib_root, 'adapters', 'input', 'command_port_adapter.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'command_port.rb')
    ]
    existing_forbidden = forbidden_files.select { |path| File.exist?(path) }

    files = Dir[File.join(root, '{lib,spec,docs}', '**', '*.{rb,md}')] + [File.join(root, 'README.md')]
    files = files.reject { |path| path.include?(File.join('spec', 'core', 'architecture')) }

    legacy_symbols = [
      const_name('Core', 'Ports', 'Outbound', 'CommandPort'),
      'command_port_adapter.rb',
      path_name('core', 'ports', 'outbound', 'command_port')
    ]
    pattern = Regexp.union(*legacy_symbols)
    referenced = files.select { |path| non_comment_content(path).match?(pattern) }

    offenders = existing_forbidden + referenced
    expect(offenders).to be_empty,
                         "Removed command-port artifacts still present:\n#{offenders.join("\n")}"
  end

  it 'forbids core/ports artifacts outside inbound/outbound trees' do
    ports_root = File.join(lib_root, 'core', 'ports')
    root_files = Dir[File.join(ports_root, '*.rb')]
    extra_dirs = Dir[File.join(ports_root, '*')].select do |path|
      File.directory?(path) && !%w[inbound outbound].include?(File.basename(path))
    end

    offenders = root_files + extra_dirs
    expect(offenders).to be_empty,
                         "Non-canonical core/ports artifacts found:\n#{offenders.join("\n")}"
  end

  it 'forbids removed adapter-local contracts from reappearing under core/ports/outbound' do
    removed_contract_files = %w[
      key_classifier
      input_system_factory
      ui_component_factory
      rendering_factory
      dictionary_ui_session
      in_book_search_ui_session
      annotation_overlay_ui_session
    ].map { |name| File.join(lib_root, 'core', 'ports', 'outbound', "#{name}.rb") }

    offenders = removed_contract_files.select { |path| File.exist?(path) }

    expect(offenders).to be_empty,
                         "Adapter-local contracts reappeared under core/ports/outbound:\n#{offenders.join("\n")}"
  end

  it 'forbids explicit legacy path mentions for removed trees' do
    files = Dir[File.join(root, '{lib,spec,docs}', '**', '*.{rb,md}')] + [File.join(root, 'README.md')]
    files = files.reject { |path| path.include?(File.join('spec', 'core', 'architecture')) }

    legacy_paths = [
      path_name('lib', 'shoko', 'application', 'controllers'),
      path_name('lib', 'shoko', 'presentation', 'ui'),
      path_name('lib', 'shoko', 'application', 'ports')
    ]

    pattern = Regexp.union(*legacy_paths)
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Legacy filesystem path mentions remain:\n#{offenders.join("\n")}"
  end
end
