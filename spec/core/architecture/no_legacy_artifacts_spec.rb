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

  def bounded_pattern(term)
    /(?<![A-Za-z0-9_])#{Regexp.escape(term)}(?![A-Za-z0-9_])/
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

    pattern = Regexp.union(*(legacy_constants + legacy_paths).map { |term| bounded_pattern(term) })
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
    pattern = Regexp.union(*legacy_symbols.map { |term| bounded_pattern(term) })
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

  it 'forbids adapter-coupled application command artifacts from reappearing' do
    removed_command_files = %w[
      application_commands
      menu_commands
      conditional_navigation_commands
      sidebar_commands
      annotation_editor_commands
      reader_commands
      reader_intent_commands
    ].map { |name| File.join(lib_root, 'application', 'use_cases', 'commands', "#{name}.rb") }

    offenders = removed_command_files.select { |path| File.exist?(path) }
    expect(offenders).to be_empty,
                         "Removed adapter-coupled application command artifacts reappeared:\n#{offenders.join("\n")}"
  end

  it 'forbids explicit legacy path mentions for removed trees' do
    files = Dir[File.join(root, '{lib,spec,docs}', '**', '*.{rb,md}')] + [File.join(root, 'README.md')]
    files = files.reject { |path| path.include?(File.join('spec', 'core', 'architecture')) }

    legacy_paths = [
      path_name('lib', 'shoko', 'application', 'controllers'),
      path_name('lib', 'shoko', 'presentation', 'ui'),
      path_name('lib', 'shoko', 'application', 'ports')
    ]

    pattern = Regexp.union(*legacy_paths.map { |term| bounded_pattern(term) })
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Legacy filesystem path mentions remain:\n#{offenders.join("\n")}"
  end

  it 'forbids deleted runtime orchestration and deprecated port tombstones from reappearing' do
    removed_files = [
      File.join(lib_root, 'application', 'reader_lifecycle.rb'),
      File.join(lib_root, 'application', 'reader_startup_orchestrator.rb'),
      File.join(lib_root, 'adapters', 'ui', 'sessions', 'session_outcome.rb'),
      File.join(lib_root, 'adapters', 'runtime', 'session_state', 'config_reader_adapter.rb'),
      File.join(lib_root, 'adapters', 'runtime', 'session_state', 'reader_state_reader_adapter.rb'),
      File.join(lib_root, 'adapters', 'runtime', 'session_state', 'ui_state_reader_adapter.rb'),
      File.join(lib_root, 'adapters', 'runtime', 'session_state', 'sidebar_state_reader_adapter.rb'),
      File.join(lib_root, 'adapters', 'runtime', 'session_state', 'menu_state_reader_adapter.rb'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'dependencies', 'menu_controller_dependencies.rb'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', 'actions', 'navigation_actions.rb'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', 'actions', 'dictionary_actions.rb'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', 'actions', 'download_actions.rb'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', 'actions', 'settings_actions.rb'),
      File.join(lib_root, 'adapters', 'runtime', 'session_state', 'state_writer_adapter.rb'),
      File.join(lib_root, 'adapters', 'runtime', 'session_state', 'menu_state_writer_adapter.rb'),
      File.join(
        lib_root,
        'bootstrap',
        'container_factory',
        'controller_composition',
        'reader_runtime_assembler',
        'context_bundles.rb'
      ),
      File.join(lib_root, 'core', 'ports', 'outbound', 'config_reader.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'menu_navigation_reader.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'menu_query_reader.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'menu_data_reader.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'menu_workflow_state_reader.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'pagination_state_writer.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'reader_navigation_reader.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'reader_state_writer.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'render_state_writer.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'sidebar_state_reader.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'ui_state_reader.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'menu_state_writer.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'menu_workflow_state_writer.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'ui_loading_writer.rb'),
      File.join(lib_root, 'core', 'ports', 'outbound', 'reader_overlay_state_reader.rb')
    ]
    existing = removed_files.select { |path| File.exist?(path) }

    files = Dir[File.join(root, '{lib,spec,docs}', '**', '*.{rb,md}')]
    files = files.reject { |path| path.include?(File.join('spec', 'core', 'architecture')) }

    legacy_terms = %w[
      application/reader_lifecycle.rb
      application/reader_startup_orchestrator.rb
      adapters/ui/sessions/session_outcome.rb
      adapters/runtime/session_state/config_reader_adapter.rb
      adapters/runtime/session_state/reader_state_reader_adapter.rb
      adapters/runtime/session_state/ui_state_reader_adapter.rb
      adapters/runtime/session_state/sidebar_state_reader_adapter.rb
      adapters/runtime/session_state/menu_state_reader_adapter.rb
      adapters/input/controllers/dependencies/menu_controller_dependencies.rb
      adapters/input/controllers/menu/actions/navigation_actions.rb
      adapters/input/controllers/menu/actions/dictionary_actions.rb
      adapters/input/controllers/menu/actions/download_actions.rb
      adapters/input/controllers/menu/actions/settings_actions.rb
      adapters/runtime/session_state/state_writer_adapter.rb
      adapters/runtime/session_state/menu_state_writer_adapter.rb
      bootstrap/container_factory/controller_composition/reader_runtime_assembler/context_bundles.rb
      core/ports/outbound/config_reader
      core/ports/outbound/menu_navigation_reader
      core/ports/outbound/menu_query_reader
      core/ports/outbound/menu_data_reader
      core/ports/outbound/menu_workflow_state_reader
      core/ports/outbound/pagination_state_writer
      core/ports/outbound/reader_navigation_reader
      core/ports/outbound/reader_state_writer
      core/ports/outbound/render_state_writer
      core/ports/outbound/sidebar_state_reader
      core/ports/outbound/ui_state_reader
      core/ports/outbound/menu_state_writer
      core/ports/outbound/menu_workflow_state_writer
      core/ports/outbound/ui_loading_writer
      core/ports/outbound/reader_overlay_state_reader
      ConfigReaderAdapter
      ReaderStateReaderAdapter
      UiStateReaderAdapter
      SidebarStateReaderAdapter
      MenuStateReaderAdapter
      ReaderCoreBundle
      ReaderWorkflowServiceBundle
      ReaderRenderingServiceBundle
      ReaderSupportServiceBundle
      ReaderServiceBundle
      ReaderSessionBundle
      ReaderRuntimeBundle
      ReaderPlatformBundle
      ReaderRuntimeAssembler::SessionBundle
      ReaderRuntimeAssembler::RuntimeStateBundle
      ReaderRuntimeAssembler::ServiceBundle
      ReaderRuntimeAssembler::UiBundle
      ReaderRuntimeAssembler::PersistenceBundle
      ReaderStateFacade
      ReaderWorkflowFacade
      ReaderRenderingFacade
      ReaderLifecycleFacade
      MenuControllerDependencies
      MenuCoreBundle
      MenuServiceBundle
      MenuPlatformBundle
      StateWriterAdapter
      MenuWorkflowStateReader
      PaginationStateWriter
      ReaderStateWriter
      RenderStateWriter
      MenuWorkflowStateWriter
      MenuStateWriterAdapter
      UiLoadingWriter
      Adapters::Ui::Sessions::SessionOutcome
    ]
    pattern = Regexp.union(*legacy_terms.map { |term| bounded_pattern(term) })
    references = files.select { |path| non_comment_content(path).match?(pattern) }

    offenders = existing + references
    expect(offenders).to be_empty,
                         "Deleted tombstone artifacts or references reappeared:\n#{offenders.join("\n")}"
  end

  it 'forbids removed gateway and reader runtime bootstrap artifacts from reappearing' do
    removed_files = [
      File.join(lib_root, 'core', 'ports', 'inbound', 'reader_command_gateway.rb'),
      File.join(lib_root, 'core', 'ports', 'inbound', 'menu_command_gateway.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'reader_gateway_command.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'menu_gateway_command.rb'),
      File.join(lib_root, 'application', 'use_cases', 'commands', 'shared_gateway_command.rb'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'reader', 'runtime_bootstrap.rb'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'dependencies', 'runtime_bootstrap_dependencies.rb')
    ]
    existing = removed_files.select { |path| File.exist?(path) }

    files = Dir[File.join(root, '{lib,spec,docs}', '**', '*.{rb,md}')] + [File.join(root, 'README.md')]
    files = files.reject { |path| path.include?(File.join('spec', 'core', 'architecture')) }

    removed_terms = %w[
      ReaderCommandGateway
      MenuCommandGateway
      ReaderGatewayCommand
      MenuGatewayCommand
      SharedGatewayCommand
      reader_command_gateway.rb
      menu_command_gateway.rb
      reader_gateway_command.rb
      menu_gateway_command.rb
      shared_gateway_command.rb
      reader/runtime_bootstrap.rb
      runtime_bootstrap_dependencies.rb
      RuntimeBootstrapDependencies
      RuntimeBootstrapServiceBundle
      RuntimeBootstrapWorkflowBundle
      RuntimeBootstrapRenderingBundle
      RuntimeBootstrapSessionSupportBundle
    ]
    pattern = Regexp.union(*removed_terms.map { |term| bounded_pattern(term) })
    references = files.select { |path| non_comment_content(path).match?(pattern) }

    offenders = existing + references
    expect(offenders).to be_empty,
                         "Removed gateway/runtime-bootstrap artifacts reappeared:\n#{offenders.join("\n")}"
  end
end
