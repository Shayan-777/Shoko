# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Hexagonal architecture boundaries' do
  let(:lib_root) { File.expand_path('../../../lib/shoko', __dir__) }

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
    allowed = %w[dependency_container.rb cli.rb]
    files = Dir[File.join(root, '**', '*.rb')].reject { |f| allowed.any? { |a| f.end_with?(a) } }
    offenders = files.select { |path| File.read(path).match?(/\bAdapters::/) }

    expect(offenders).to be_empty,
                         "Application files reference adapters outside composition root:\n#{offenders.join("\n")}"
  end

  it 'avoids ENV access in application sources (outside composition root)' do
    root = File.join(lib_root, 'application')
    allowed = %w[dependency_container.rb cli.rb]
    files = Dir[File.join(root, '**', '*.rb')].reject { |f| allowed.any? { |a| f.end_with?(a) } }
    offenders = files.select { |path| File.read(path).include?('ENV[') }

    expect(offenders).to be_empty,
                         "Application files access ENV outside composition root:\n#{offenders.join("\n")}"
  end

  it 'restricts .resolve() calls to composition root files' do
    root = File.join(lib_root, 'application')
    # Only true composition roots may call .resolve() — everything else receives dependencies via constructor
    composition_roots = %w[
      dependency_container.rb
      cli.rb
      unified_application.rb
    ]
    files = Dir[File.join(root, '**', '*.rb')].reject do |f|
      composition_roots.any? { |cr| f.end_with?(cr) }
    end
    offenders = files.select { |path| File.read(path).include?('.resolve(') }

    expect(offenders).to be_empty,
                         "Non-composition-root files use .resolve():\n#{offenders.join("\n")}"
  end

  it 'ensures core services do not depend on DI container' do
    core_services = Dir[File.join(lib_root, 'core', 'services', '**', '*.rb')]
    offenders = core_services.select { |f| File.read(f).include?('.resolve(') }

    expect(offenders).to be_empty,
                         "Core services call .resolve() (service locator anti-pattern):\n#{offenders.join("\n")}"
  end

  it 'avoids class-level singleton configuration outside composition root' do
    # Class-level attribute assignment (e.g. Logger.output = ...) should only happen
    # in composition root files, not scattered through production code
    composition_roots = %w[dependency_container.rb cli.rb]
    all_rb = Dir[File.join(lib_root, '**', '*.rb')].reject do |f|
      composition_roots.any? { |cr| f.end_with?(cr) } ||
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
      # comments, and third-party library configuration (e.g. REXML::Security)
      lines.reject! { |line| line.match?(/attr_|Thread\.current|self\.\w+\s*=|#|REXML::/) }
      lines.any?
    end

    expect(offenders).to be_empty,
                         "Files with class-level singleton configuration:\n#{offenders.join("\n")}"
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
end
