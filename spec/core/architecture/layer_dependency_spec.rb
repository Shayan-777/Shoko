# frozen_string_literal: true

require 'spec_helper'

# Consolidated layer-boundary rules (constitution sections 1 and 9). Absorbs
# the former adapter_boundary, strict_hexagonal_wiring, layer_policy_consistency,
# no_cross_adapter_runtime_coupling specs and the general layer-purity
# examples of the retired hexagonal_* and application_workflow suites.
RSpec.describe 'Layer dependency boundaries' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:layer_policy) { SpecSupport::Architecture::LayerPolicy }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  end

  def non_comment_lines(path)
    File.readlines(path).each_with_index.filter_map do |line, index|
      next if line.strip.start_with?('#')

      [index + 1, line]
    end
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
          next unless layer_for(target_rel)
          next if layer_policy.allows_path?(source_layer, target_rel, source_path: source_rel)

          offenders << "#{source_rel} -> #{target_rel}"
        end
      end

      expect(offenders).to be_empty,
                           "Layer dependency violations:\n#{offenders.uniq.sort.join("\n")}"
    end

    it 'keeps adapters isolated from application dependencies in the shared policy' do
      expect(layer_policy.allowed_targets_for('adapters')).not_to include('application')
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

    # One example for one rule: renderer types are application-owned, so core
    # neither defines nor names them. (Two separate DisplayLine pins — one for
    # the constant, one for any textual reference — were the same rule twice.)
    it 'keeps renderer types out of core' do
      defined_in_core = Shoko::Core::Models.constants(false).grep(/DisplayLine/)
      referencing = Dir[File.join(lib_root, 'core', '**', '*.rb')].select do |path|
        non_comment_content(path).match?(/\bDisplayLine\b/)
      end.map { |path| relative(path) }

      expect(defined_in_core + referencing).to eq([]),
                                               'DisplayLine is a renderer type owned by ' \
                                               "Application::Ports::Outbound::Formatting; core must depend on " \
                                               "method shape (String-vs-other), not on it:\n" \
                                               "#{(defined_in_core + referencing).join("\n")}"
    end
  end

  describe 'application purity' do
    it 'forbids adapter constants in application sources' do
      files = Dir[File.join(lib_root, 'application', '**', '*.rb')]
      offenders = files.select { |path| non_comment_content(path).match?(/\bAdapters::/) }

      expect(offenders).to be_empty, "Application files reference adapters:\n#{offenders.join("\n")}"
    end

    # The rule, not a list of the four method names that happened to violate
    # it: a controller is an input-adapter object, so the application layer
    # must not call ANY method on one. Naming the methods pinned a moment and
    # let the fifth coupling method through (constitution section 9).
    it 'forbids the application layer from calling controller methods' do
      files = Dir[File.join(lib_root, 'application', '**', '*.rb')]
      pattern = /(?<![\w.])@?controller\.[a-z_][\w!?]*/

      offenders = files.flat_map do |path|
        non_comment_lines(path).filter_map do |line_no, line|
          next unless (match = line.match(pattern))

          "#{relative(path)}:#{line_no}: #{match[0]}"
        end
      end

      expect(offenders).to be_empty,
                           "Application layer orchestrates adapter controller API directly:\n#{offenders.sort.join("\n")}"
    end

    # Terminal I/O is an output-adapter capability reached through ports.
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
          next if layer_policy.allows_path?('adapters', target, source_path: source)

          offenders << "#{source}:#{line} -> #{target}"
        end
      end

      expect(offenders).to be_empty,
                           "Adapters require application files directly:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids adapters from referencing application constants' do
      files = Dir[File.join(lib_root, 'adapters', '**', '*.rb')]
      pattern = /\b(?:Shoko::)?Application::/
      # The constant spellings of the same PATH_EXCEPTIONS the policy declares.
      permitted = layer_policy.exceptions_for('adapters').map do |prefix|
        namespace = prefix.delete_prefix('application/').split('/').reject(&:empty?)
                          .map { |segment| segment.split('_').map(&:capitalize).join }
        /\b(?:Shoko::)?Application::#{namespace.join('::')}::/
      end
      offenders = []

      files.each do |path|
        source = relative(path)
        non_comment_lines(path).each do |line_no, line|
          next if permitted.any? { |allowed| line.match?(allowed) }
          next unless line.match?(pattern)

          offenders << "#{source}:#{line_no}: #{line.strip}"
        end
      end

      expect(offenders).to be_empty,
                           "Adapters reference application constants directly:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids every adapter family from referencing sibling adapter constants' do
      files = Dir[File.join(lib_root, 'adapters', '**', '*.rb')]
      pattern = /\b(?:Shoko::)?Adapters::([A-Z][A-Za-z0-9]*)::/
      offenders = []

      files.each do |path|
        source = relative(path)
        non_comment_lines(path).each do |line_no, line|
          line.scan(pattern).flatten.each do |namespace|
            target_family = namespace.gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase
            target = "adapters/#{target_family}/"
            next if layer_policy.allows_adapter_dependency?(source, target)

            offenders << "#{source}:#{line_no}: #{line.strip}"
          end
        end
      end

      expect(offenders).to be_empty,
                           "Adapter families reference sibling adapter constants instead of ports, core/shared " \
                           "values, or adapters/support:\n#{offenders.uniq.sort.join("\n")}"
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
