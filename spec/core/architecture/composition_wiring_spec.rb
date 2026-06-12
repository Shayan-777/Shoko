# frozen_string_literal: true

require 'spec_helper'

# Consolidated composition rules (constitution §I: only composition names and
# wires concrete classes; §IV: the composition root is plain wiring). Absorbs
# the container-access examples of the former adapter_boundary suite, the
# controller_composition suite, and the live wiring rules of the
# reader_render_session_view suite.
RSpec.describe 'Composition is the only concrete wiring' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:container_resolution_pattern) { /(?:@container|\bcontainer\b|\bc\b)\.(resolve|resolve_optional)\(/ }
  let(:container_mutation_pattern) { /(?:@container|\bcontainer\b|\bc\b)\.(register|register_factory|register_singleton|unregister)\(/ }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def relative(path)
    path.delete_prefix("#{lib_root}/")
  end

  def composition_roots
    [
      'composition/container_factory.rb',
      'composition/dependency_container.rb',
      'composition/format_registry_composition.rb',
      'composition/runtime_composition.rb',
      'composition/container_factory/controller_composition.rb',
      'composition/container_factory/controller_composition/menu_builder.rb',
      'composition/container_factory/controller_composition/reader_builder.rb',
      'composition/container_factory/controller_composition/reader_runtime_assembler.rb',
      'composition/container_factory/controller_composition/menu_state_controller_composer.rb',
      'composition/container_factory/domain_application_registration.rb',
      'composition/container_factory/infrastructure_registration.rb',
      'composition/container_factory/port_and_repository_registration.rb',
      'composition/container_factory/test_container_registration.rb',
      'test_support/test_mode.rb',
    ]
  end

  def composition_root_prefixes
    [
      'composition/container_factory/domain_application_registration/',
      'composition/container_factory/port_and_repository_registration/',
      'composition/container_factory/controller_composition/reader_builder/',
      'composition/container_factory/controller_composition/menu_builder/',
    ]
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

  it 'allows reader controller graph construction only in the composition root' do
    allowed_paths = [
      File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'reader_builder.rb'),
      File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'reader_runtime_assembler.rb'),
      File.join(lib_root, 'composition', 'container_factory', 'controller_composition',
                'menu_state_controller_composer.rb'),
    ]
    allowed_prefixes = [
      "#{File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'reader_builder')}/",
      "#{File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'reader_runtime_assembler')}/",
    ]
    controller_names = %w[
      UIController
      StateController
      SidebarController
      DictionaryController
      AnnotationOverlayController
      InBookSearchController
    ]

    offenders = []
    Dir[File.join(lib_root, '**', '*.rb')].each do |path|
      next if allowed_paths.include?(path) || allowed_prefixes.any? { |prefix| path.start_with?(prefix) }

      File.readlines(path).each_with_index do |line, index|
        content = line.sub(/\s+#.*\z/, '')

        controller_names.each do |name|
          qualified = /\b(?:Shoko::)?Adapters::Input::Controllers::#{name}\.new\b/
          short = /\b#{name}\.new\b/

          next unless content.match?(qualified) || content.match?(short)
          next if name == 'StateController' &&
                  content.match?(/\b(?:Shoko::)?Adapters::Input::Controllers::Menu::StateController\.new\b/)
          next if name == 'StateController' && content.match?(/\bMenu::StateController\.new\b/)

          offenders << "#{relative(path)}:#{index + 1} #{name}.new"
        end
      end
    end

    expect(offenders).to eq([]),
                         "Controller graph composition escaped the composition root:\n#{offenders.sort.join("\n")}"
  end

  it 'keeps the reader/menu composition render slice off legacy read-port resolutions' do
    files = %w[
      composition/container_factory.rb
      composition/container_factory/controller_composition/reader_builder.rb
      composition/container_factory/controller_composition/menu_builder.rb
    ].map { |path| File.join(lib_root, path) }

    forbidden_patterns = [
      /resolve\(:config_reader\)/,
      /resolve\(:reader_state_reader\)/,
      /resolve\(:reader_navigation_reader\)/,
      /resolve\(:ui_state_reader\)/,
      /resolve\(:sidebar_state_reader\)/,
      /resolve\(:menu_state_reader\)/,
    ]

    offenders = files.filter_map do |path|
      content = non_comment_content(path)
      next unless forbidden_patterns.any? { |pattern| content.match?(pattern) }

      relative(path)
    end

    expect(offenders).to eq([]),
                         "Reader render/output composition slice still resolves legacy read ports:\n#{offenders.join("\n")}"
  end

  it 'wires reader runtime assembler ui/render consumers to the broad reader state projection' do
    runtime_files = Dir[
      File.join(lib_root, 'composition', 'container_factory', 'controller_composition',
                'reader_runtime_assembler', '**', '*.rb')
    ]
    forbidden_patterns = [
      /reader_state_reader:\s*(?:context|runtime_context)\.state\.reader_session_store/,
      /reader_state:\s*(?:context|runtime_context)\.state\.reader_session_store/,
    ]

    offenders = runtime_files.filter_map do |path|
      content = non_comment_content(path)
      next unless forbidden_patterns.any? { |pattern| content.match?(pattern) }

      relative(path)
    end

    expect(offenders).to eq([]),
                         "Reader runtime assembler still wires session-only state into UI/render consumers:\n#{offenders.join("\n")}"
  end
end
