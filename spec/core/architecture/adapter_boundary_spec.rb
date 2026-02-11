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
      cli_progress_renderer.rb
      composition/container_factory/controller_composition.rb
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
    allowed = %w[dependency_container.rb cli.rb]
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

  it 'restricts container resolution calls to composition root files' do
    root = File.join(lib_root, 'application')
    # Only true composition roots may resolve from the container — everything else
    # receives dependencies via constructor injection.
    composition_roots = %w[
      dependency_container.rb
      cli.rb
      unified_application.rb
      composition/container_factory/controller_composition.rb
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
      adapters/input/command_bridge.rb
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
      composition/container_factory/controller_composition.rb
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

  it 'keeps orchestration facades below complexity guardrails' do
    thresholds = {
      'application/controllers/menu/state_controller.rb' => 320,
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
end
