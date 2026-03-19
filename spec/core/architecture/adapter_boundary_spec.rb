# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Hexagonal architecture boundaries' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:container_resolution_pattern) { /(?:@container|\bcontainer\b|\bc\b)\.(resolve|resolve_optional)\(/ }
  let(:container_mutation_pattern) { /(?:@container|\bcontainer\b|\bc\b)\.(register|register_factory|register_singleton|unregister)\(/ }

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

  def relative(path)
    path.delete_prefix("#{lib_root}/")
  end

  def composition_roots
    [
      path_name('composition', 'container_factory.rb'),
      path_name('composition', 'dependency_container.rb'),
      path_name('composition', 'format_registry_composition.rb'),
      path_name('composition', 'runtime_composition.rb'),
      path_name('composition', 'container_factory', 'controller_composition.rb'),
      path_name('composition', 'container_factory', 'controller_composition', 'menu_builder.rb'),
      path_name('composition', 'container_factory', 'controller_composition', 'reader_builder.rb'),
      path_name('composition', 'container_factory', 'controller_composition', 'reader_runtime_assembler.rb'),
      path_name('composition', 'container_factory', 'controller_composition', 'menu_state_controller_composer.rb'),
      path_name('composition', 'container_factory', 'domain_application_registration.rb'),
      path_name('composition', 'container_factory', 'infrastructure_registration.rb'),
      path_name('composition', 'container_factory', 'port_and_repository_registration.rb'),
      path_name('composition', 'container_factory', 'test_container_registration.rb'),
      path_name('test_support', 'test_mode.rb')
    ]
  end

  def composition_root_prefixes
    [
      "#{path_name('composition', 'container_factory', 'domain_application_registration')}/",
      "#{path_name('composition', 'container_factory', 'controller_composition', 'reader_builder')}/",
      "#{path_name('composition', 'container_factory', 'controller_composition', 'menu_builder')}/"
    ]
  end

  it 'uses a single core ports root split by inbound/outbound' do
    ports_root = File.join(lib_root, 'core', 'ports')
    inbound = File.join(ports_root, 'inbound')
    outbound = File.join(ports_root, 'outbound')

    expect(Dir.exist?(inbound)).to eq(true), "Missing inbound ports directory: #{inbound}"
    expect(Dir.exist?(outbound)).to eq(true), "Missing outbound ports directory: #{outbound}"

    unexpected_dirs = Dir[File.join(ports_root, '*')].select do |path|
      File.directory?(path) && !%w[inbound outbound].include?(File.basename(path))
    end
    root_files = Dir[File.join(ports_root, '*.rb')]

    expect(unexpected_dirs + root_files).to be_empty,
                                             "Non-canonical core/ports artifacts found:\n#{(unexpected_dirs + root_files).join("\n")}"
  end

  it 'forbids adapter constants in core sources' do
    files = Dir[File.join(lib_root, 'core', '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).include?(const_name('Shoko', 'Adapters')) }

    expect(offenders).to be_empty, "Core files reference adapters:\n#{offenders.join("\n")}"
  end

  it 'forbids adapter constants in application sources' do
    files = Dir[File.join(lib_root, 'application', '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(/\bAdapters::/) }

    expect(offenders).to be_empty, "Application files reference adapters:\n#{offenders.join("\n")}"
  end

  it 'forbids ui adapter dependencies on sibling adapters' do
    files = Dir[File.join(lib_root, 'adapters', 'ui', '**', '*.rb')]
    require_pattern = /require_relative\s+['"][^'"]*adapters\/(?:output|input|storage|runtime|monitoring|book_sources)\//
    const_pattern = /\b(?:Shoko::)?Adapters::(?:Output|Input|Storage|Runtime|Monitoring|BookSources)::/

    offenders = files.select do |path|
      content = non_comment_content(path)
      content.match?(require_pattern) || content.match?(const_pattern)
    end

    expect(offenders).to be_empty,
                             "UI adapters depend on sibling adapters instead of shared/core boundaries:\n#{offenders.join("\n")}"
  end

  it 'restricts container resolution to composition roots' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select do |path|
      next false unless non_comment_content(path).match?(container_resolution_pattern)

      rel = relative(path)
      !composition_roots.any? { |allowed| rel.end_with?(allowed) } &&
        !composition_root_prefixes.any? { |prefix| rel.start_with?(prefix) }
    end

    expect(offenders).to be_empty,
                         "Container resolution used outside composition roots:\n#{offenders.join("\n")}"
  end

  it 'restricts container mutation to composition roots' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select do |path|
      next false unless non_comment_content(path).match?(container_mutation_pattern)

      rel = relative(path)
      !composition_roots.any? { |allowed| rel.end_with?(allowed) } &&
        !composition_root_prefixes.any? { |prefix| rel.start_with?(prefix) }
    end

    expect(offenders).to be_empty,
                         "Container mutation used outside composition roots:\n#{offenders.join("\n")}"
  end
end
