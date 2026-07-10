# frozen_string_literal: true

require 'spec_helper'

# Typed collaborators over reflection (constitution §V): dependencies are
# injected with known contracts, so `respond_to?` probing and `send`-style
# dispatch are banned. Absorbs the reflection examples of the retired
# hexagonal_migration/hardening/application_workflow suites.
RSpec.describe 'No reflection probing' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'forbids reflection-based dispatch and collaborator probing in strict scope' do
    strict_roots = [
      File.join(lib_root, 'core'),
      File.join(lib_root, 'application'),
      File.join(lib_root, 'adapters', 'runtime'),
      File.join(lib_root, 'composition'),
    ]
    files = strict_roots.flat_map { |root_path| Dir[File.join(root_path, '**', '*.rb')] }
    pattern = /\brespond_to\?\(|\bpublic_send\b|\bsend\s*\(/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "Strict scope must not use reflection probing/dispatch:\n" \
                         "#{offenders.map { |p| p.delete_prefix("#{root}/") }.join("\n")}"
  end

  # Probing an injected collaborator for a method its contract guarantees is a
  # silent-failure trap: a rename passes every test with permissive doubles
  # while the feature quietly stops working. In UI/input adapters `respond_to?`
  # is therefore banned too, except for:
  #   * Ruby protocol-conversion probes on values (:to_h, :to_sym, :call, …),
  #     which normalize external/loose data rather than probe collaborators; and
  #   * the allowlisted files below, each probing a genuinely polymorphic or
  #     external surface (raw IO capabilities, importer-specific documents,
  #     the formatting layer's "config-like" values, parsed render geometry,
  #     heterogeneous screen collections, dynamic command validation, or
  #     fail-fast argument checks that raise instead of skipping).
  it 'forbids respond_to? probing of guaranteed collaborators in adapters and shared' do
    allowlist = %w[
      adapters/monitoring/logger_adapter.rb
      adapters/input/controllers/reader/inline_link/destination_resolver.rb
      adapters/input/dispatcher.rb
      adapters/storage/recent_files_repository.rb
      adapters/rss/rss_reader_service.rb
      adapters/output/formatting/formatting_service.rb
      adapters/output/terminal/input.rb
      adapters/output/kitty/kitty_graphics.rb
      adapters/ui/rendering/line/config_helpers.rb
      adapters/ui/components/main_menu_component.rb
      adapters/ui/components/ui/backdrop_overlay.rb
      adapters/ui/view_models/reader_view_model_builder.rb
      adapters/ui/sessions/dictionary_ui_session_adapter.rb
      shared/lazy_proxy.rb
      shared/language_directory.rb
    ].map { |rel| File.join(lib_root, rel) }

    scoped_roots = [File.join(lib_root, 'adapters'), File.join(lib_root, 'shared')]
    files = scoped_roots.flat_map { |root_path| Dir[File.join(root_path, '**', '*.rb')] }
    protocol_probe = /respond_to\?\(:(?:to_[a-z]+\??|call|each|key\?|\[\]=?)\)/
    offenders = files.reject { |path| allowlist.include?(path) }.select do |path|
      content = non_comment_content(path)
      content.gsub(protocol_probe, '').match?(/\brespond_to\?\(/)
    end

    expect(offenders).to eq([]),
                         "Adapters/shared must not respond_to?-probe guaranteed collaborators " \
                         "(call directly; genuine polymorphic boundaries join the allowlist " \
                         "with a justification):\n" \
                         "#{offenders.map { |p| p.delete_prefix("#{root}/") }.join("\n")}"
  end

  # Signature probing is the same trap through a different door: inspecting a
  # collaborator's method parameters (`x.method(:foo).parameters`,
  # `klass.instance_method(:initialize).parameters`) to adapt a call defends
  # against contracts the ports already pin, and silently drops arguments when
  # a signature drifts. Callers rely on the declared contract instead.
  it 'forbids method-signature probing everywhere in lib' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /\.parameters\b|\barity\b/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "lib must not probe method signatures (rely on the declared contract; " \
                         "unify the collaborators' signatures instead):\n" \
                         "#{offenders.map { |p| p.delete_prefix("#{root}/") }.join("\n")}"
  end
end
