# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Hexagonal architecture boundaries' do
  let(:lib_root) { File.expand_path('../../../lib/shoko', __dir__) }
  let(:env_pattern) { /\bENV\s*(?:\[|\.fetch\s*\()/ }
  let(:container_mutation_pattern) { /\.(register|register_factory|register_singleton|unregister)\(/ }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'avoids adapter constants in core sources' do
    root = File.join(lib_root, 'core')
    files = Dir[File.join(root, '**', '*.rb')]
    offenders = files.select do |path|
      File.read(path).include?('Shoko::Adapters::')
    end

    expect(offenders).to be_empty, "Core files reference adapters:\n#{offenders.join("\n")}"
  end

  it 'avoids adapter constants in application sources (outside composition root)' do
    root = File.join(lib_root, 'application')
    allowed = %w[
      dependency_container.rb
      cli.rb
      cli_progress_presenter.rb
      composition/bootstrap/format_registry_bootstrap.rb
      composition/bootstrap/runtime_bootstrap.rb
      composition/container_factory/controller_composition.rb
      composition/container_factory/controller_composition/menu_builder.rb
      composition/container_factory/controller_composition/reader_builder.rb
      composition/container_factory/domain_application_registration.rb
      composition/container_factory/infrastructure_registration.rb
      composition/container_factory/port_and_repository_registration.rb
      composition/container_factory/test_container_registration.rb
    ]
    files = Dir[File.join(root, '**', '*.rb')].reject { |f| allowed.any? { |a| f.end_with?(a) } }
    offenders = files.select { |path| File.read(path).match?(/\bAdapters::/) }

    expect(offenders).to be_empty,
                         "Application files reference adapters outside composition root:\n#{offenders.join("\n")}"
  end

  it 'avoids ENV access in application sources (outside composition root)' do
    root = File.join(lib_root, 'application')
    allowed = %w[
      dependency_container.rb
      cli.rb
      composition/bootstrap/runtime_bootstrap.rb
    ]
    files = Dir[File.join(root, '**', '*.rb')].reject { |f| allowed.any? { |a| f.end_with?(a) } }
    offenders = files.select { |path| non_comment_content(path).match?(env_pattern) }

    expect(offenders).to be_empty,
                         "Application files access ENV outside composition root:\n#{offenders.join("\n")}"
  end

  it 'avoids ENV access in core sources' do
    root = File.join(lib_root, 'core')
    files = Dir[File.join(root, '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(env_pattern) }

    expect(offenders).to be_empty,
                         "Core files access ENV directly:\n#{offenders.join("\n")}"
  end

  it 'forbids direct ENV access in adapters outside runtime config and approved terminal/path cases' do
    root = File.join(lib_root, 'adapters')
    allowed = %w[
      runtime/env_runtime_config_adapter.rb
      output/terminal/terminal.rb
      output/kitty/kitty_graphics.rb
      output/kitty/image_transcoder.rb
      output/clipboard/clipboard_service.rb
      storage/config_paths.rb
      storage/cache_paths.rb
    ]
    files = Dir[File.join(root, '**', '*.rb')].reject { |f| allowed.any? { |a| f.end_with?(a) } }
    offenders = files.select { |path| non_comment_content(path).match?(env_pattern) }

    expect(offenders).to be_empty,
                         "Adapters access ENV directly outside approved boundaries:\n#{offenders.join("\n")}"
  end

  it 'restricts container resolution calls to composition root files' do
    root = File.join(lib_root, 'application')
    # Only true composition roots may resolve from the container — everything else
    # receives dependencies via constructor injection.
    composition_roots = %w[
      dependency_container.rb
      cli.rb
      unified_application.rb
      composition/bootstrap/format_registry_bootstrap.rb
      composition/bootstrap/runtime_bootstrap.rb
      composition/container_factory/controller_composition.rb
      composition/container_factory/controller_composition/menu_builder.rb
      composition/container_factory/controller_composition/reader_builder.rb
      composition/container_factory/domain_application_registration.rb
      composition/container_factory/infrastructure_registration.rb
      composition/container_factory/port_and_repository_registration.rb
      composition/container_factory/test_container_registration.rb
    ]
    files = Dir[File.join(root, '**', '*.rb')].reject do |f|
      composition_roots.any? { |cr| f.end_with?(cr) }
    end
    resolve_pattern = /\.(resolve|resolve_optional)\(/
    offenders = files.select { |path| File.read(path).match?(resolve_pattern) }

    expect(offenders).to be_empty,
                         "Non-composition-root files resolve dependencies from container:\n#{offenders.join("\n")}"
  end

  it 'ensures core services do not depend on DI container' do
    core_services = Dir[File.join(lib_root, 'core', 'services', '**', '*.rb')]
    resolve_pattern = /\.(resolve|resolve_optional)\(/
    offenders = core_services.select { |f| File.read(f).match?(resolve_pattern) }

    expect(offenders).to be_empty,
                         "Core services resolve from DI container (service locator anti-pattern):\n#{offenders.join("\n")}"
  end

  it 'forbids service-locator resolution in output UI adapters and wrapping service' do
    ui_files = Dir[File.join(lib_root, 'adapters', 'output', 'ui', '**', '*.rb')]
    wrapping_file = File.join(lib_root, 'adapters', 'output', 'formatting', 'wrapping_service.rb')
    files = ui_files + [wrapping_file]
    resolve_pattern = /\.(resolve|resolve_optional)\(/
    offenders = files.select { |path| File.read(path).match?(resolve_pattern) }

    expect(offenders).to be_empty,
                         "Output adapters resolve dependencies at runtime:\n#{offenders.join("\n")}"
  end

  it 'forbids legacy factory call shapes that thread a container through adapters' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    patterns = {
      /create_frame_coordinator\(\s*[a-zA-Z_]\w*\s*\)/ =>
        'RenderingFactory#create_frame_coordinator must use keyword dependencies',
      /create_render_pipeline\(\s*[a-zA-Z_]\w*\s*\)/ =>
        'RenderingFactory#create_render_pipeline must use keyword dependencies',
      /create_reader_render_coordinator\(\s*dependencies:/ =>
        'RenderingFactory#create_reader_render_coordinator must receive typed reader dependencies',
      /main_menu_component\(\s*self\s*,\s*dependencies:/ =>
        'UIComponentFactory#main_menu_component must receive menu_ui_dependencies',
      /annotation_editor_screen\(\s*controller:\s*[^,]+,\s*dependencies:/ =>
        'UIComponentFactory#annotation_editor_screen must receive explicit services'
    }

    offenders = []
    files.each do |path|
      content = non_comment_content(path)
      patterns.each do |pattern, message|
        offenders << "#{path}: #{message}" if content.match?(pattern)
      end
    end

    expect(offenders).to be_empty,
                         "Legacy container-threading factory calls found:\n#{offenders.join("\n")}"
  end

  it 'avoids container resolution in input command routing adapters' do
    resolve_pattern = /\.(resolve|resolve_optional)\(/
    files = %w[
      adapters/input/command_factory.rb
      adapters/input/input_controller.rb
    ].map { |relative| File.join(lib_root, relative) }

    offenders = files.select { |path| File.read(path).match?(resolve_pattern) }

    expect(offenders).to be_empty,
                         "Input adapters resolve dependencies from container at runtime:\n#{offenders.join("\n")}"
  end

  it 'forbids filesystem/env policy primitives in dictionary orchestration and dictionary settings UI files' do
    files = %w[
      application/use_cases/settings_service.rb
      application/workflows/menu/dictionary_workflow.rb
      application/controllers/dictionary/setup_flow/download_support.rb
      adapters/output/ui/components/screens/dictionary_settings_screen_component.rb
    ].map { |relative| File.join(lib_root, relative) }

    policy_pattern = /
      \bENV\s*(?:\[|\.fetch\s*\()|
      \bDir\.home\b|
      \bFile\.(?:expand_path|realpath)\b|
      \bFileUtils\.(?:mkdir_p|rm_rf|rm_f)\b
    /x
    offenders = files.select { |path| non_comment_content(path).match?(policy_pattern) }

    expect(offenders).to be_empty,
                         "Dictionary flow/UI files contain filesystem or ENV policy logic:\n#{offenders.join("\n")}"
  end

  it 'forbids legacy .local/share dictionary path fallback outside adapters' do
    files = Dir[File.join(lib_root, 'application', '**', '*.rb')] +
            Dir[File.join(lib_root, 'adapters', 'output', 'ui', '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).include?('.local/share/shoko/dictionaries') }

    expect(offenders).to be_empty,
                         "Legacy dictionary fallback path literal found:\n#{offenders.join("\n")}"
  end

  it 'forbids direct SqliteDictionaryAdapter coupling in dictionary settings screen component' do
    path = File.join(lib_root, 'adapters', 'output', 'ui', 'components', 'screens',
                     'dictionary_settings_screen_component.rb')

    expect(non_comment_content(path)).not_to include('SqliteDictionaryAdapter'),
                                         'DictionarySettingsScreenComponent must use injected ports, not adapter constants'
  end

  it 'restricts container mutation calls to composition roots' do
    root = File.join(lib_root, 'application')
    composition_roots = %w[
      dependency_container.rb
      cli.rb
      unified_application.rb
      composition/bootstrap/format_registry_bootstrap.rb
      composition/bootstrap/runtime_bootstrap.rb
      composition/container_factory/controller_composition.rb
      composition/container_factory/controller_composition/menu_builder.rb
      composition/container_factory/controller_composition/reader_builder.rb
      composition/container_factory/domain_application_registration.rb
      composition/container_factory/infrastructure_registration.rb
      composition/container_factory/port_and_repository_registration.rb
      composition/container_factory/test_container_registration.rb
    ]
    files = Dir[File.join(root, '**', '*.rb')].reject do |f|
      composition_roots.any? { |cr| f.end_with?(cr) }
    end
    offenders = files.select { |path| non_comment_content(path).match?(container_mutation_pattern) }

    expect(offenders).to be_empty,
                         "Non-composition files mutate container registrations:\n#{offenders.join("\n")}"
  end

  it 'ensures controllers never mutate container registrations' do
    root = File.join(lib_root, 'application', 'controllers')
    files = Dir[File.join(root, '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(container_mutation_pattern) }

    expect(offenders).to be_empty,
                         "Controllers mutate DI container registrations:\n#{offenders.join("\n")}"
  end

  it 'avoids class-level singleton configuration in core sources' do
    core_files = Dir[File.join(lib_root, 'core', '**', '*.rb')]
    singleton_pattern = /\b[A-Z]\w+\.\w+\s*=/
    offenders = core_files.select do |path|
      lines = non_comment_content(path).lines.select { |line| line.match?(singleton_pattern) }
      lines.reject! { |line| line.match?(/attr_|Thread\.current|self\.\w+\s*=/) }
      lines.any?
    end

    expect(offenders).to be_empty,
                         "Core files contain class-level singleton mutation:\n#{offenders.join("\n")}"
  end

  it 'avoids class-level singleton configuration outside composition root' do
    # Class-level attribute assignment (e.g. Logger.output = ...) should only happen
    # in composition root files, not scattered through production code
    composition_roots = %w[dependency_container.rb cli.rb]
    explicit_allowlist = %w[adapters/runtime/rexml_security_limits_adapter.rb]
    all_rb = Dir[File.join(lib_root, '**', '*.rb')].reject do |f|
      composition_roots.any? { |cr| f.end_with?(cr) } ||
        explicit_allowlist.any? { |allowed| f.end_with?(allowed) } ||
        f.include?('test_support') ||
        f.include?('spec')
    end

    # Pattern: ClassName.attr = value (class-level singleton mutation)
    singleton_pattern = /\b[A-Z]\w+\.\w+\s*=/
    offenders = all_rb.select do |path|
      content = File.read(path)
      # Match class-level attribute assignment, excluding:
      # - attr_accessor/attr_writer definitions
      # - Thread.current assignments (thread-local, not global)
      # - self.foo = (instance method definitions)
      lines = content.lines.select { |line| line.match?(singleton_pattern) }
      # Exclude: attr definitions, thread-local storage, instance method self-assigns,
      # and comments.
      lines.reject! { |line| line.match?(/attr_|Thread\.current|self\.\w+\s*=|#/) }
      lines.any?
    end

    expect(offenders).to be_empty,
                         "Files with class-level singleton configuration:\n#{offenders.join("\n")}"
  end

  it 'ensures no controller uses @state.get or @state.dispatch directly' do
    root = File.join(lib_root, 'application', 'controllers')
    files = Dir[File.join(root, '**', '*.rb')]
    offenders = files.select do |path|
      content = File.read(path)
      content.match?(/@state\.get\b/) || content.match?(/@state\.dispatch\b/)
    end

    expect(offenders).to be_empty,
                         "Controllers access state store directly:\n#{offenders.join("\n")}"
  end

  it 'ensures no controller references Selectors directly' do
    root = File.join(lib_root, 'application', 'controllers')
    files = Dir[File.join(root, '**', '*.rb')]
    offenders = files.select do |path|
      content = File.read(path)
      content.match?(/Selectors::\w+Selectors/)
    end

    expect(offenders).to be_empty,
                         "Controllers reference Selectors directly instead of using ports:\n#{offenders.join("\n")}"
  end

  it 'ensures every port has at least one adapter implementation' do
    ports_root = File.join(lib_root, 'core', 'ports')
    port_files = Dir[File.join(ports_root, '**', '*.rb')]
    # Scan all source files — implementations live in adapters/, application/adapters/, and core/services/
    all_source = Dir[File.join(lib_root, '**', '*.rb')].reject { |f| f.start_with?(ports_root) }
    adapter_source = all_source.map { |f| File.read(f) }.join("\n")

    unimplemented = port_files.select do |port_path|
      # Extract module name from the port file
      content = File.read(port_path)
      # Find module declarations like "module KeyClassifier"
      modules = content.scan(/module (\w+)/).flatten
      # Skip base/namespace modules
      port_modules = modules.reject { |m| %w[Shoko Core Ports Services].include?(m) }
      next true if port_modules.empty?

      # Check if any adapter includes any of these port modules
      port_modules.none? { |mod| adapter_source.include?('include') && adapter_source.match?(/include\b.*\b#{mod}\b/) }
    end

    expect(unimplemented).to be_empty,
                             "Ports with no adapter implementation:\n#{unimplemented.join("\n")}"
  end

  it 'forbids ConfigBridge references' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select { |path| File.read(path).match?(/\bConfigBridge\b/) }

    expect(offenders).to be_empty,
                         "ConfigBridge references must be removed:\n#{offenders.join("\n")}"
  end

  it 'forbids NotificationService#set_message legacy arity (state, text, duration)' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /\b(?:notification_service|@notification_service)\s*&?\.?\s*set_message\s*\(\s*nil\s*,/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Legacy NotificationService#set_message(state, ...) usage found:\n#{offenders.join("\n")}"
  end

  it 'forbids NotificationService#tick state argument usage' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /\b(?:notification_service|@notification_service)\s*&?\.?\s*tick\s*\(\s*[^)]/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "NotificationService#tick must be called with no args:\n#{offenders.join("\n")}"
  end

  it 'forbids register_*_bindings_new naming in InputController' do
    path = File.join(lib_root, 'adapters', 'input', 'input_controller.rb')
    content = File.read(path)
    offenders = content.scan(/\bregister_[a-z_]+_bindings_new\b/).uniq

    expect(offenders).to be_empty,
                             "Rename InputController bindings methods to canonical names:\n#{offenders.join("\n")}"
  end

  it 'forbids direct filesystem/process primitives in application layer outside explicit boundaries' do
    root = File.join(lib_root, 'application')
    allowed = %w[
      cli.rb
      composition/container_factory/controller_composition.rb
      composition/container_factory/controller_composition/menu_builder.rb
      composition/container_factory/controller_composition/reader_builder.rb
      composition/container_factory/domain_application_registration.rb
      composition/container_factory/infrastructure_registration.rb
      composition/container_factory/port_and_repository_registration.rb
      composition/container_factory/test_container_registration.rb
    ]
    files = Dir[File.join(root, '**', '*.rb')].reject { |f| allowed.any? { |a| f.end_with?(a) } }
    primitives = /
      \bFile\.
      |\bDir\.
      |\bFileUtils\.
      |\bPathname\b
      |\bProcess\.clock_gettime\b
      |\bKernel\.exit\b
      |(?:^|\s)exit\s*(?:\(|$)
    /x
    offenders = files.select { |path| non_comment_content(path).match?(primitives) }

    expect(offenders).to be_empty,
                         "Application files contain IO/process primitives outside boundaries:\n#{offenders.join("\n")}"
  end

  it 'forbids direct file/archive IO primitives in core book format parsers' do
    root = File.join(lib_root, 'core', 'book_formats')
    files = Dir[File.join(root, '**', '*.rb')]
    io_pattern = /\bFile\.|\bDir\.|\bFileUtils\.|\bPathname\b|\bZip::File\.open\b/
    offenders = files.select { |path| non_comment_content(path).match?(io_pattern) }

    expect(offenders).to be_empty,
                         "Core book format files contain direct IO primitives:\n#{offenders.join("\n")}"
  end

  it 'forbids test-runtime toggles in production lib code' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /defined\?\(RSpec\)|Thread\.current\[:suppress_event_errors\]/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Production code contains test-only runtime toggles:\n#{offenders.join("\n")}"
  end

  it 'requires dependency-object constructors for top-level controllers and runtime bootstrap' do
    checks = {
      'application/controllers/reader_controller.rb' => /def initialize\(epub_path,\s*deps:\)/,
      'application/controllers/menu_controller.rb' => /def initialize\(deps:\)/,
      'application/controllers/reader/runtime_bootstrap.rb' => /def initialize\(deps:\)/
    }
    offenders = checks.filter_map do |relative_path, pattern|
      path = File.join(lib_root, relative_path)
      next if File.read(path).match?(pattern)

      path
    end

    expect(offenders).to be_empty,
                         "Missing dependency-object constructor signatures:\n#{offenders.join("\n")}"
  end

  it 'forbids retired jumbo state port references across runtime sources' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /ports\/(reader_state_reader|menu_state_reader|state_writer)|Core::Ports::(?:ReaderStateReader|MenuStateReader|StateWriter)/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Runtime sources still reference retired jumbo ports:\n#{offenders.join("\n")}"
  end

  it 'forbids new popup/menu/loading semantics inside core services' do
    files = Dir[File.join(lib_root, 'core', 'services', '**', '*.rb')]
    pattern = /popup_menu|dictionary_popup|in_book_search_popup|annotations_overlay|annotation_editor_overlay|update_ui_loading|update_menu\(/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Core services encode UI/menu/popup/loading semantics:\n#{offenders.join("\n")}"
  end

  it 'forbids deprecated core UI/menu port shim files from existing' do
    forbidden = %w[
      core/ports/menu_navigation_reader.rb
      core/ports/menu_query_reader.rb
      core/ports/menu_data_reader.rb
      core/ports/menu_state_writer.rb
      core/ports/reader_overlay_reader.rb
    ]
    offenders = forbidden.map { |relative| File.join(lib_root, relative) }.select { |path| File.file?(path) }

    expect(offenders).to be_empty,
                         "Deprecated core UI/menu port shim files still exist:\n#{offenders.join("\n")}"
  end

  it 'forbids application-layer references to deprecated core UI/menu ports' do
    files = Dir[File.join(lib_root, 'application', '**', '*.rb')]
    pattern = /core\/ports\/(menu_navigation_reader|menu_query_reader|menu_data_reader|menu_state_writer|reader_overlay_reader)|Core::Ports::(?:MenuNavigationReader|MenuQueryReader|MenuDataReader|MenuStateWriter|ReaderOverlayReader)/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Application layer still references deprecated core UI/menu ports:\n#{offenders.join("\n")}"
  end

  it 'forbids adapter-layer references to deprecated core UI/menu ports' do
    files = Dir[File.join(lib_root, 'adapters', '**', '*.rb')]
    pattern = /core\/ports\/(menu_navigation_reader|menu_query_reader|menu_data_reader|menu_state_writer|reader_overlay_reader)|Core::Ports::(?:MenuNavigationReader|MenuQueryReader|MenuDataReader|MenuStateWriter|ReaderOverlayReader)/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Adapter layer still references deprecated core UI/menu ports:\n#{offenders.join("\n")}"
  end

  it 'keeps core UI-coupled port files as compatibility aliases only' do
    relative_paths = %w[
      core/ports/ui_state_reader.rb
      core/ports/sidebar_state_reader.rb
      core/ports/input_system_factory.rb
      core/ports/pagination_state_writer.rb
      core/ports/reader_state_writer.rb
    ]
    offenders = relative_paths.filter_map do |relative_path|
      path = File.join(lib_root, relative_path)
      next unless File.file?(path)

      content = non_comment_content(path)
      has_alias = content.match?(/=\s*Shoko::Application::Ports::|include\s+Shoko::Application::Ports::/)
      has_definitions = content.match?(/^\s*def\s+/)
      next if has_alias && !has_definitions

      path
    end

    expect(offenders).to be_empty,
                         "Core UI-coupled port files must remain alias-only compatibility shims:\n#{offenders.join("\n")}"
  end

  it 'forbids references to removed core pagination wrapper constants and files' do
    files = Dir[File.join(lib_root, '**', '*.rb')] + Dir[File.expand_path('../../**/*.rb', __dir__)]
    pattern = /Core::Services::Pagination::(?:PageInfoCalculator|PaginationOrchestrator|PaginationCoordinator)|core\/services\/pagination\/(?:page_info_calculator|pagination_orchestrator|pagination_coordinator)/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "References to removed core pagination wrappers remain:\n#{offenders.join("\n")}"
  end

  it 'forbids direct Core::Services construction in controllers and workflows' do
    files = Dir[File.join(lib_root, 'application', 'controllers', '**', '*.rb')] +
            Dir[File.join(lib_root, 'application', 'workflows', '**', '*.rb')]
    pattern = /Core::Services::[A-Za-z0-9_:]+\.new/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Controllers/workflows instantiate core services directly:\n#{offenders.join("\n")}"
  end

  it 'forbids workflow dependencies on controller modules' do
    files = Dir[File.join(lib_root, 'application', 'workflows', '**', '*.rb')]
    pattern = /require_relative\s+['"][^'"]*controllers\/|Application::Controllers::/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Workflows depend on controller modules:\n#{offenders.join("\n")}"
  end

  it 'forbids BookFinder class-method compatibility API usage across runtime sources' do
    files = Dir[File.join(lib_root, '**', '*.rb')] + Dir[File.expand_path('../../**/*.rb', __dir__)]
    pattern = /BookFinder\.(?:configure|install_default|scan_system|clear_cache|config_dir)\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "BookFinder class-level compatibility API usage remains:\n#{offenders.join("\n")}"
  end

  it 'forbids BookFinder compatibility class-method definitions' do
    path = File.join(lib_root, 'adapters', 'book_sources', 'book_finder.rb')
    content = non_comment_content(path)
    pattern = /class\s*<<\s*self|def\s+self\.(?:configure|install_default|scan_system|clear_cache|config_dir)\b/

    expect(content).not_to match(pattern),
                           'BookFinder must expose instance-only API (no compatibility class methods)'
  end

  it 'forbids raw terminal key literal escapes in application sources' do
    root = File.join(lib_root, 'application')
    files = Dir[File.join(root, '**', '*.rb')]
    # keep this focused on control-sequence style literals; plain chars are allowed
    pattern = /\\e\[(?:A|B)|\\eO(?:A|B)|\\x13|\\x7F/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Application files contain raw terminal key literals:\n#{offenders.join("\n")}"
  end

  it 'forbids direct UI component lifecycle calls in application controllers' do
    root = File.join(lib_root, 'application', 'controllers')
    files = Dir[File.join(root, '**', '*.rb')]
    pattern = /(?:dictionary_panel|dictionary_popup|in_book_search_popup|annotations_overlay|annotation_editor_overlay|popup_menu)\s*&?\.?\s*(?:visible\?|show|hide|handle_key)\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Application controllers manipulate UI component lifecycles directly:\n#{offenders.join("\n")}"
  end

  it 'forbids direct context dispatch fallback in input command execution' do
    path = File.join(lib_root, 'adapters', 'input', 'commands.rb')
    content = non_comment_content(path)
    offenders = []
    offenders << path if content.match?(/def execute_symbol/)
    offenders << path if content.match?(/context\.respond_to\?\(/)
    offenders << path if content.match?(/context\.public_send\(/)

    expect(offenders).to be_empty,
                         "Input command execution still falls back to direct context dispatch:\n#{offenders.uniq.join("\n")}"
  end

  it 'forbids legacy command bridge and context method command references' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /\bCommandBridge\b|\bContextMethodCommand\b|context_method_command/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Legacy command bridge references remain:\n#{offenders.join("\n")}"
  end

  it 'forbids raw key handler contract in UI session ports' do
    files = %w[
      application/ports/dictionary_ui_session.rb
      application/ports/in_book_search_ui_session.rb
      application/ports/annotation_overlay_ui_session.rb
    ].map { |relative| File.join(lib_root, relative) }
    offenders = files.select { |path| non_comment_content(path).match?(/def\s+handle_key\b/) }

    expect(offenders).to be_empty,
                         "UI session ports still expose raw key handling:\n#{offenders.join("\n")}"
  end

  it 'forbids legacy annotation overlay session bridge classes' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /AnnotationEditorOverlaySession|OverlaySessionCoordinator|overlay_session_coordinator/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Legacy annotation overlay bridge references remain:\n#{offenders.join("\n")}"
  end

  it 'requires explicit constructor signature in MouseableReader' do
    path = File.join(lib_root, 'application/controllers/mouseable_reader.rb')
    content = non_comment_content(path)

    expect(content).not_to match(/def\s+initialize\([^\)]*\*\*kwargs/),
                           'MouseableReader constructor must not accept **kwargs'
  end

  it 'forbids legacy dictionary/in-book generic handle command symbols' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /dictionary_handle_key|in_book_search_handle_key/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Legacy generic key-forward command symbols remain:\n#{offenders.join("\n")}"
  end

  it 'forbids context respond_to? plus public_send fallback in command classes' do
    files = %w[
      application/use_cases/commands/menu_commands.rb
      application/use_cases/commands/application_commands.rb
      application/use_cases/commands/annotation_editor_commands.rb
    ].map { |relative| File.join(lib_root, relative) }
    offenders = files.select do |path|
      content = non_comment_content(path)
      content.match?(/context\.respond_to\?\(/) && content.match?(/public_send\(/)
    end

    expect(offenders).to be_empty,
                         "Command classes still use dynamic respond_to?/public_send fallback:\n#{offenders.join("\n")}"
  end

  it 'forbids direct state store APIs in application command classes' do
    root = File.join(lib_root, 'application', 'use_cases', 'commands')
    files = Dir[File.join(root, '**', '*.rb')]
    pattern = /@state\.|\bstate\.(?:get|set|update)\(/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Application command classes still use direct state store APIs:\n#{offenders.join("\n")}"
  end

  it 'forbids UI component reach-through in application command classes' do
    root = File.join(lib_root, 'application', 'use_cases', 'commands')
    files = Dir[File.join(root, '**', '*.rb')]
    pattern = /\bmain_menu_component\b|\bannotations_screen\b|\bbrowse_screen\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Application command classes reach into concrete UI components:\n#{offenders.join("\n")}"
  end

  it 'forbids adapter references in application CLI progress presenter' do
    path = File.join(lib_root, 'application', 'cli_progress_presenter.rb')
    content = non_comment_content(path)
    pattern = /\bAdapters::|require_relative\s+['"][^'"]*adapters\//

    expect(content).not_to match(pattern),
                           'CLI progress presenter must not reference adapter constants or adapter require paths'
  end

  it 'forbids legacy Application::Commands namespace references' do
    files = Dir[File.join(lib_root, '**', '*.rb')] + Dir[File.expand_path('../../**/*.rb', __dir__)]
    files = files.reject { |path| path.end_with?('spec/core/architecture/adapter_boundary_spec.rb') }
    offenders = files.select { |path| non_comment_content(path).include?('Shoko::Application::Commands') }

    expect(offenders).to be_empty,
                         "Legacy Application::Commands namespace references found:\n#{offenders.join("\n")}"
  end

  it 'forbids references to removed input key definitions wrapper' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /require_relative\s+['"][^'"]*input\/key_definitions['"]|Adapters::Input::KeyDefinitions/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Sources still reference removed input key definitions wrapper:\n#{offenders.join("\n")}"
  end

  it 'forbids input validators from depending on output UI constants' do
    files = Dir[File.join(lib_root, 'adapters', 'input', 'validators', '**', '*.rb')]
    pattern = /Adapters::Output::Ui::Constants::UI/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Input validators still depend on output UI constants:\n#{offenders.join("\n")}"
  end

  it 'forbids reflection-based ivar access in output UI sessions' do
    files = Dir[File.join(lib_root, 'adapters', 'output', 'ui', 'sessions', '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(/instance_variable_get\(/) }

    expect(offenders).to be_empty,
                         "Output UI sessions still use instance_variable_get reflection:\n#{offenders.join("\n")}"
  end

  it 'forbids reflection dispatch and private reach-through in application controllers' do
    files = Dir[File.join(lib_root, 'application', 'controllers', '**', '*.rb')]
    patterns = [
      /\b\.send\s*\(/,
      /\b\.public_send\s*\(/,
      /respond_to\?\([^)]*,\s*true\)/
    ]
    offenders = files.select do |path|
      content = non_comment_content(path)
      patterns.any? { |pattern| content.match?(pattern) }
    end

    expect(offenders).to be_empty,
                         "Application controllers use reflection-based dispatch/private reach-through:\n#{offenders.join("\n")}"
  end

  it 'forbids direct time primitives in application controllers and workflows' do
    files = Dir[File.join(lib_root, 'application', 'controllers', '**', '*.rb')] +
            Dir[File.join(lib_root, 'application', 'workflows', '**', '*.rb')]
    pattern = /\bTime\.now\b|\bProcess\.clock_gettime\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Application controllers/workflows use direct time primitives:\n#{offenders.join("\n")}"
  end

  it 'forbids adapter dependencies on core internal service implementations' do
    files = Dir[File.join(lib_root, 'adapters', '**', '*.rb')]
    pattern = /require_relative\s+['"][^'"]*core\/services\/[^'"]*\/internal\/|Core::Services::[A-Za-z0-9_:]+::Internal::/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Adapters depend on core internal service implementations:\n#{offenders.join("\n")}"
  end

  it 'forbids broad StandardError rescues in UI session adapters' do
    files = Dir[File.join(lib_root, 'adapters', 'output', 'ui', 'sessions', '*_ui_session_adapter.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(/rescue\s+StandardError/) }

    expect(offenders).to be_empty,
                         "UI session adapters still use broad StandardError rescue:\n#{offenders.join("\n")}"
  end

  it 'forbids removed bookmark legacy bridge and legacy bookmark event symbols in runtime sources' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /\bBookmarkLegacyEventBridge\b|\bbookmark_legacy_event_bridge\b|:bookmark_added\b|:bookmark_removed\b|:navigated_to_bookmark\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Runtime sources still reference removed bookmark legacy bridge/symbols:\n#{offenders.join("\n")}"
  end

  it 'forbids TOC shim references and files' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /toc_tab_support/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Sources still reference removed TOC shim:\n#{offenders.join("\n")}"
  end

  it 'forbids legacy ObserverStateStore two-argument update signature' do
    path = File.join(lib_root, 'adapters', 'state', 'observer_state_store.rb')
    content = non_comment_content(path)

    expect(content).not_to match(/def\s+update\s*\([^)]*,[^)]*\)/),
                           'ObserverStateStore#update must only accept a single hash argument'
  end

  it 'keeps dependency bundle objects under field-count guardrails' do
    max_fields = 28
    files = Dir[File.join(lib_root, 'application', 'composition', 'dependencies', '**', '*.rb')]
    offenders = []

    files.each do |path|
      content = non_comment_content(path)
      match = content.match(/=\s*(?:Struct\.new|Data\.define)\((.*?)\)\s*do/m)
      next unless match

      field_count = match[1].scan(/:\w+/).length
      offenders << "#{path} (#{field_count} > #{max_fields})" if field_count > max_fields
    end

    expect(offenders).to be_empty,
                         "Dependency bundle objects exceeded field count guardrails:\n#{offenders.join("\n")}"
  end

  it 'keeps orchestration facades below complexity guardrails' do
    thresholds = {
      'application/controllers/menu_controller.rb' => 320,
      'application/controllers/ui_controller.rb' => 320,
      'application/controllers/state_controller.rb' => 260,
      'application/controllers/menu/state_controller.rb' => 320,
      'application/composition/container_factory/controller_composition.rb' => 140,
      'application/controllers/reader_controller.rb' => 420,
      'adapters/storage/book_cache_pipeline.rb' => 250,
    }
    offenders = thresholds.filter_map do |relative_path, max_lines|
      path = File.join(lib_root, relative_path)
      next unless File.file?(path)

      lines = File.readlines(path).length
      "#{path} (#{lines} > #{max_lines})" if lines > max_lines
    end

    expect(offenders).to be_empty,
                         "Facade files exceeded complexity thresholds:\n#{offenders.join("\n")}"
  end

  it 'catches safe-navigation state bypass in controllers and commands' do
    roots = [
      File.join(lib_root, 'application', 'controllers'),
      File.join(lib_root, 'application', 'use_cases', 'commands'),
    ]
    files = roots.flat_map { |root| Dir[File.join(root, '**', '*.rb')] }
    # Match both @state.get/dispatch and state&.get/dispatch (safe-navigation bypass)
    pattern = /@state[&.](?:get|dispatch|update)\b|\bstate[&.](?:get|dispatch|update)\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Controllers/commands use direct state store APIs (including &. bypass):\n#{offenders.join("\n")}"
  end

  it 'forbids cross-adapter dependencies from book_sources to storage adapters' do
    root = File.join(lib_root, 'adapters', 'book_sources')
    files = Dir[File.join(root, '**', '*.rb')]
    # These specific storage adapter classes were eliminated in Phase 4
    pattern = /Storage::ConfigPaths|Storage::CachePaths|Storage::AtomicFileWriter/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "BookSources adapters reference storage adapter classes directly:\n#{offenders.join("\n")}"
  end

  it 'forbids cross-adapter dependencies from output to book_sources adapters' do
    root = File.join(lib_root, 'adapters', 'output')
    files = Dir[File.join(root, '**', '*.rb')]
    pattern = /require_relative\s+['"][^'"]*book_sources/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Output adapters reference book_sources adapters via require_relative:\n#{offenders.join("\n")}"
  end

  it 'forbids global_state parameters in port interfaces' do
    port_dirs = [
      File.join(lib_root, 'core', 'ports'),
      File.join(lib_root, 'application', 'ports'),
    ]
    files = port_dirs.flat_map { |dir| Dir[File.join(dir, '**', '*.rb')] }
    offenders = files.select { |path| non_comment_content(path).match?(/\bglobal_state\b/) }

    expect(offenders).to be_empty,
                         "Port interfaces expose implementation detail 'global_state':\n#{offenders.join("\n")}"
  end

  it 'forbids StateStore class references outside state adapters and composition root' do
    all_files = Dir[File.join(lib_root, '**', '*.rb')]
    allowed_dirs = %w[adapters/state/ application/composition/ application/dependency_container.rb]
    files = all_files.reject do |f|
      allowed_dirs.any? { |dir| f.include?(dir) } || f.end_with?('shoko.rb')
    end
    pattern = /\bObserverStateStore\b|\bStateStore\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "StateStore/ObserverStateStore referenced outside state adapters and composition root:\n#{offenders.join("\n")}"
  end

  it 'limits lib/shoko.rb to composition bootstrap entrypoint requires' do
    path = File.join(File.expand_path('../..', lib_root), 'lib', 'shoko.rb')
    content = non_comment_content(path)
    require_lines = content.lines.grep(/^\s*require_relative\s+/).map(&:strip)
    allowed = ["require_relative 'shoko/application/composition/bootstrap/runtime_bootstrap'"]

    expect(require_lines - allowed).to be_empty,
                                        "lib/shoko.rb has non-bootstrap requires:\n#{(require_lines - allowed).join("\n")}"
    expect(content).not_to match(/FormatRegistry\.register|Shoko::Core::BookFormats::FormatRegistry\.register/),
                           'lib/shoko.rb must not perform runtime format registration directly'
  end
end
