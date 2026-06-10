# frozen_string_literal: true

require 'spec_helper'

# Consolidated layer-boundary rules (constitution §I: the dependency rule;
# §V: one spec per rule family). Absorbs the former adapter_boundary,
# strict_hexagonal_wiring, layer_policy_consistency,
# no_cross_adapter_runtime_coupling specs and the general layer-purity
# examples of the retired hexagonal_* and application_workflow suites.
RSpec.describe 'Layer dependency boundaries' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:layer_policy) { SpecSupport::Architecture::LayerPolicy }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def non_comment_lines(path)
    File.readlines(path).each_with_index.filter_map do |line, index|
      next if line.strip.start_with?('#')

      [index + 1, line]
    end
  rescue StandardError
    []
  end

  def layer_for(relative_path)
    relative_path.split('/').first
  end

  def relative(path)
    path.delete_prefix("#{lib_root}/")
  end

  def require_relative_targets(file_path)
    content = non_comment_content(file_path)
    content.scan(/^\s*require_relative\s+['"]([^'"]+)['"]/).flatten.filter_map do |raw|
      target = raw.end_with?('.rb') ? raw : "#{raw}.rb"
      expanded = File.expand_path(target, File.dirname(file_path))
      next unless expanded.start_with?(lib_root)

      relative(expanded)
    end
  end

  def require_shoko_targets(file_path)
    content = non_comment_content(file_path)
    content.scan(/^\s*require\s+['"](shoko\/[^'"]+)['"]/).flatten.map do |raw|
      rel = raw.sub(/\Ashoko\//, '')
      rel.end_with?('.rb') ? rel : "#{rel}.rb"
    end
  end

  def dependency_targets(file_path)
    (require_relative_targets(file_path) + require_shoko_targets(file_path)).uniq
  end

  def require_relative_targets_with_lines(path)
    File.readlines(path).each_with_index.filter_map do |line, index|
      match = line.match(/^\s*require_relative\s+['"]([^'"]+)['"]/)
      next unless match

      raw = match[1]
      target = raw.end_with?('.rb') ? raw : "#{raw}.rb"
      expanded = File.expand_path(target, File.dirname(path))
      next unless expanded.start_with?(lib_root)

      [index + 1, relative(expanded)]
    end
  rescue StandardError
    []
  end

  describe 'layer matrix' do
    it 'enforces strict layer dependency matrix' do
      files = Dir[File.join(lib_root, '**', '*.rb')]
      offenders = []

      files.each do |file_path|
        source_rel = relative(file_path)
        source_layer = layer_for(source_rel)
        next unless layer_policy::MATRIX.key?(source_layer)

        dependency_targets(file_path).each do |target_rel|
          target_layer = layer_for(target_rel)
          next unless target_layer
          next if target_rel.start_with?('application/ports/')
          next if source_rel.start_with?('adapters/input/') && target_rel.start_with?('application/use_cases/requests/')
          next if layer_policy.allows?(source_layer, target_layer)

          offenders << "#{source_rel} -> #{target_rel}"
        end
      end

      expect(offenders).to be_empty,
                           "Layer dependency violations:\n#{offenders.uniq.sort.join("\n")}"
    end

    it 'keeps adapters isolated from application dependencies in the shared policy' do
      expect(layer_policy.allowed_targets_for('adapters')).not_to include('application')
    end

    it 'forces layer boundary specs to use the shared layer policy helper' do
      offenders = [__FILE__].reject { |path| File.read(path).include?('SpecSupport::Architecture::LayerPolicy') }

      expect(offenders).to be_empty,
                           "Layer boundary specs must use shared policy helper:\n#{offenders.sort.join("\n")}"
    end
  end

  describe 'core purity' do
    it 'forbids adapter constants in core sources' do
      files = Dir[File.join(lib_root, 'core', '**', '*.rb')]
      offenders = files.select { |path| non_comment_content(path).include?('Shoko::Adapters') }

      expect(offenders).to be_empty, "Core files reference adapters:\n#{offenders.join("\n")}"
    end

    # The domain core depends on nothing outward — not even application-owned
    # ports. The matrix globally exempts `application/ports/` requires (so
    # adapters may use ports), but the core is held to the stricter rule:
    # depend on method *shape*, not on any application type. See audit ARCH-1.
    it 'forbids application constants in core sources' do
      files = Dir[File.join(lib_root, 'core', '**', '*.rb')]
      offenders = files.select { |path| non_comment_content(path).match?(/\b(?:Shoko::)?Application::/) }

      expect(offenders).to be_empty,
                           "Core sources reference application constructs (depend on method shape via duck typing, " \
                           "not on application-owned types/ports):\n#{offenders.join("\n")}"
    end

    it 'forbids core sources from requiring application files' do
      files = Dir[File.join(lib_root, 'core', '**', '*.rb')]
      require_pattern = %r{require(?:_relative)?\s+['"][^'"]*application/}
      offenders = files.select { |path| non_comment_content(path).match?(require_pattern) }

      expect(offenders).to be_empty,
                           "Core sources require application files (closes the application/ports require exemption " \
                           "for core specifically):\n#{offenders.join("\n")}"
    end

    it 'keeps DisplayLine out of core (Core::Models::DisplayLine must not be defined)' do
      offender = Shoko::Core::Models.constants(false).find { |name| name == :DisplayLine }

      expect(offender).to be_nil,
                          'DisplayLine is a renderer type and must not live in Core::Models. ' \
                          'Its canonical home is Application::Ports::Outbound::Formatting::DisplayLine.'
    end

    it 'forbids any DisplayLine constant reference inside core/' do
      offenders = Dir[File.join(lib_root, 'core', '**', '*.rb')].select do |path|
        non_comment_content(path).match?(/\bDisplayLine\b/)
      end

      expect(offenders).to eq([]),
                          "Core files referencing DisplayLine (use String-vs-other duck pattern instead):\n" \
                          "#{offenders.map { |p| relative(p) }.join("\n")}"
    end
  end

  describe 'application purity' do
    it 'forbids adapter constants in application sources' do
      files = Dir[File.join(lib_root, 'application', '**', '*.rb')]
      offenders = files.select { |path| non_comment_content(path).match?(/\bAdapters::/) }

      expect(offenders).to be_empty, "Application files reference adapters:\n#{offenders.join("\n")}"
    end

    it 'forbids application layer dependencies on controller runtime APIs' do
      files = Dir[File.join(lib_root, 'application', '**', '*.rb')]
      patterns = {
        'controller.state_controller coupling' => /\bcontroller\.state_controller\b/,
        'controller.main_loop coupling' => /\bcontroller\.main_loop\b/,
        'controller metrics mutation coupling' => /\bcontroller\.mark_metrics_start!\b/,
        'controller observer cleanup coupling' => /\bcontroller\.cleanup_observers\b/,
      }

      offenders = files.flat_map do |path|
        content = non_comment_content(path)
        patterns.filter_map do |label, pattern|
          next unless content.match?(pattern)

          "#{relative(path)}: #{label}"
        end
      end

      expect(offenders).to be_empty,
                           "Application layer still orchestrates controller runtime API directly:\n#{offenders.join("\n")}"
    end

    it 'forbids terminal_service dependencies in application layer' do
      files = Dir[File.join(lib_root, 'application', '**', '*.rb')]
      offenders = files.select { |path| non_comment_content(path).match?(/\bterminal_service\b/) }

      expect(offenders).to be_empty,
                           "Application layer still depends on terminal_service:\n#{offenders.join("\n")}"
    end

    it 'forbids File.* / IO.* in lib/shoko/application/' do
      pattern = /\b(?:File|IO)\.[A-Za-z_]/
      offenders = Dir[File.join(lib_root, 'application', '**', '*.rb')].filter_map do |path|
        next unless non_comment_content(path).match?(pattern)

        relative(path)
      end

      expect(offenders).to be_empty,
                           "Application layer must use ports for I/O; offenders:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids context.ui_controller/state_controller across the application layer' do
      # Repointed (audit ARCH-5) from the now-removed commands directory to the
      # whole application layer: the command concept moved to the reader/menu
      # action use-cases, which receive a routing `context`. No other guardrail
      # catches this method-call-level coupling — so this guards a real seam.
      files = Dir[File.join(lib_root, 'application', '**', '*.rb')]
      pattern = /\bcontext\.(?:ui_controller|state_controller)\b/
      offenders = files.filter_map do |path|
        rel = relative(path)
        next unless non_comment_content(path).match?(pattern)

        rel
      end

      expect(offenders).to be_empty,
                           "Application use-cases couple to adapter controller API via context:\n#{offenders.sort.join("\n")}"
    end
  end

  describe 'adapter discipline' do
    it 'forbids adapters from requiring application files' do
      files = Dir[File.join(lib_root, 'adapters', '**', '*.rb')]
      offenders = []

      files.each do |path|
        source = relative(path)
        require_relative_targets_with_lines(path).each do |line, target|
          target_layer = target.split('/').first
          next if target.start_with?('application/ports/')
          next if target.start_with?('application/use_cases/requests/')
          next if layer_policy.allows?('adapters', target_layer)

          offenders << "#{source}:#{line} -> #{target}"
        end
      end

      expect(offenders).to be_empty,
                           "Adapters require application files directly:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids adapters from referencing application constants' do
      files = Dir[File.join(lib_root, 'adapters', '**', '*.rb')]
      pattern = /\b(?:Shoko::)?Application::/
      offenders = []

      files.each do |path|
        source = relative(path)
        non_comment_lines(path).each do |line_no, line|
          next if line.match?(/\b(?:Shoko::)?Application::Ports::/)
          next if line.match?(/\b(?:Shoko::)?Application::UseCases::Requests::/)
          next unless line.match?(pattern)

          offenders << "#{source}:#{line_no}: #{line.strip}"
        end
      end

      expect(offenders).to be_empty,
                           "Adapters reference application constants directly:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids adapters/input from referencing adapters/ui constants directly' do
      files = Dir[File.join(lib_root, 'adapters', 'input', '**', '*.rb')]
      pattern = /\b(?:Shoko::)?Adapters::Ui::/
      offenders = []

      files.each do |path|
        source = relative(path)
        non_comment_lines(path).each do |line_no, line|
          next unless line.match?(pattern)

          offenders << "#{source}:#{line_no}: #{line.strip}"
        end
      end

      expect(offenders).to be_empty,
                           "Input adapters reference UI adapter constants directly:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids ui adapter dependencies on sibling adapters' do
      files = Dir[File.join(lib_root, 'adapters', 'ui', '**', '*.rb')]
      require_pattern = %r{require_relative\s+['"][^'"]*adapters/(?:output|input|storage|runtime|monitoring|book_sources)/}
      const_pattern = /\b(?:Shoko::)?Adapters::(?:Output|Input|Storage|Runtime|Monitoring|BookSources)::/

      offenders = files.select do |path|
        content = non_comment_content(path)
        content.match?(require_pattern) || content.match?(const_pattern)
      end

      expect(offenders).to be_empty,
                           "UI adapters depend on sibling adapters instead of shared/core boundaries:\n#{offenders.join("\n")}"
    end

    it 'forbids output adapters from referencing runtime adapter namespace directly' do
      output_root = File.join(lib_root, 'adapters', 'output')
      offenders = Dir[File.join(output_root, '**', '*.rb')].filter_map do |path|
        next unless File.read(path).match?(/\bAdapters::Runtime::/)

        relative(path)
      end

      expect(offenders).to eq([]),
                           "Output adapters must depend on outbound ports/shared abstractions, not Adapters::Runtime:\n#{offenders.join("\n")}"
    end

    it 'forbids storage adapters from referencing book-source or output adapters' do
      storage_root = File.join(lib_root, 'adapters', 'storage')
      offenders = Dir[File.join(storage_root, '**', '*.rb')].filter_map do |path|
        content = File.read(path)
        next unless content.match?(%r{\bAdapters::(?:BookSources|Output)::|adapters/(?:book_sources|output)/})

        relative(path)
      end

      expect(offenders).to eq([]),
                           "Storage adapters must not call sibling adapters:\n#{offenders.join("\n")}"
    end

    it 'forbids non-UI runtime files from using UI theme normalization helpers' do
      offenders = Dir[File.join(lib_root, '**', '*.rb')].filter_map do |path|
        next if path.include?(File.join('adapters', 'ui'))

        content = File.read(path)
        next unless content.match?(/Themes\.(normalize_theme|valid_theme\?)/)

        relative(path)
      end

      expect(offenders).to eq([]),
                           "Theme identity policy must live outside UI constants:\n#{offenders.join("\n")}"
    end
  end

  describe 'shared and composition reach' do
    # The shared layer may load its OWN bundled data files (unicode tables,
    # codepoint maps) and provide pure utilities over a caller-supplied path,
    # but must not derive application semantics from the filesystem.
    SHARED_IO_EXEMPT_FILES = [
      'shared/optional_dependency.rb',                  # gem-load probing
      'shared/source_fingerprint.rb',                   # SHA over an input path
      'shared/terminal/kitty_unicode_placeholders.rb',  # bundled codepoint table
      'shared/unicode_display_width.rb',                # bundled width table
    ].freeze

    it 'forbids File.* / IO.* in lib/shoko/shared/ (modulo audited exemptions)' do
      pattern = /\b(?:File|IO)\.[A-Za-z_]/
      offenders = Dir[File.join(lib_root, 'shared', '**', '*.rb')].filter_map do |path|
        next unless non_comment_content(path).match?(pattern)

        relative(path)
      end - SHARED_IO_EXEMPT_FILES

      expect(offenders).to be_empty,
                           "Shared layer is a pure-utility leaf; offenders:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids local requires into composition from application and adapters' do
      files = Dir[File.join(lib_root, '{application,adapters}', '**', '*.rb')]
      offenders = files.filter_map do |path|
        rel = relative(path)
        targets = dependency_targets(path)
        next if targets.none? { |target| target.start_with?('composition/') }

        rel
      end

      expect(offenders).to be_empty,
                           "Application/adapters require composition files:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids local requires into adapters from shared' do
      files = Dir[File.join(lib_root, 'shared', '**', '*.rb')]
      offenders = files.filter_map do |path|
        rel = relative(path)
        targets = dependency_targets(path)
        next if targets.none? { |target| target.start_with?('adapters/') }

        rel
      end

      expect(offenders).to be_empty,
                           "Shared requires adapter files:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids Shoko::Composition constants outside composition, bin, and test_support' do
      files = Dir[File.join(lib_root, '**', '*.rb')]
      offenders = files.filter_map do |path|
        rel = relative(path)
        next if rel.start_with?('composition/') || rel.start_with?('test_support/')
        next unless non_comment_content(path).match?(/\bShoko::Composition::/)

        rel
      end

      expect(offenders).to be_empty,
                           "Shoko::Composition constants referenced outside allowed areas:\n#{offenders.sort.join("\n")}"
    end
  end
end
