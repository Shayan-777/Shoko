# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Layer dependency boundaries' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:layer_policy) { SpecSupport::Architecture::LayerPolicy }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
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

  it 'forbids context.ui_controller/state_controller across the application layer' do
    # Repointed (audit ARCH-5) from the now-removed commands directory to the
    # whole application layer: the command concept moved to the reader/menu
    # action use-cases, which receive a routing `context`. No other guardrail
    # catches this method-call-level coupling (command_dispatch bans legacy type
    # names; adapter_boundary catches constant refs) — so this guards a real seam.
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
