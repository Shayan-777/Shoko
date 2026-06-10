# frozen_string_literal: true

require 'spec_helper'

# Typed collaborators over reflection (constitution §V): inside the strict
# scope — core, application, adapters/runtime, composition — dependencies are
# injected with known contracts, so `respond_to?` probing and `send`-style
# dispatch are banned. Adapter UI/input code that integrates with optional
# capabilities sits outside this scope. Absorbs the reflection examples of
# the retired hexagonal_migration/hardening/application_workflow suites.
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
end
