# frozen_string_literal: true

require 'spec_helper'

# Constitution §III: no `_support`, `_helper(s)`, `_coordinator`, `_dispatch`,
# `_mixin(s)`, `_actions` file suffix unless that word is a real role/domain
# concept. True Coordinator roles (pagination_coordinator, frame_coordinator,
# spellcheck_coordinator, selection_coordinator) are real patterns and not
# banned. The pre-rule ratchet allowlist closed on 2026-07-11 — every holdout
# was renamed to a role noun or folded into its host, so the ban now holds
# with no exceptions.
RSpec.describe 'Naming banlist' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  BANNED_SUFFIX_GLOBS = %w[
    *_support.rb
    *_helper.rb
    *_helpers.rb
    *_mixin.rb
    *_mixins.rb
    *_actions.rb
    *_dispatch.rb
  ].freeze

  # The ratchet closed on 2026-07-11: the last pre-rule holdouts were renamed
  # to role nouns or folded into their hosts. No allowlist remains — any
  # banned-suffix file is a violation.
  it 'forbids files with banned grab-bag suffixes' do
    offenders = BANNED_SUFFIX_GLOBS.flat_map do |glob|
      Dir[File.join(lib_root, '**', glob)]
    end.map { |path| path.delete_prefix("#{lib_root}/") }

    expect(offenders).to eq([]),
                         "Banned-suffix files (constitution §III — name the role, or keep private methods " \
                         "on the host):\n#{offenders.sort.join("\n")}"
  end

  it 'forbids shorthand module declarations in runtime code' do
    pattern = /^\s*module [A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)+/
    offenders = Dir[File.join(lib_root, '**', '*.rb')].filter_map do |path|
      next unless File.foreach(path).any? { |line| line.match?(pattern) }

      path.delete_prefix("#{root}/")
    end

    expect(offenders).to be_empty,
                         "Shorthand module declarations must not be used:\n#{offenders.sort.join("\n")}"
  end

  # §III: "a file is named after the single class/module it defines."
  # Enforced by SingleConstantFileScanner: one root constant per file whose
  # short name matches the basename (case-insensitively, directory-scoped
  # prefixes allowed), all other definitions nested inside it. Namespace
  # reopenings, require-only aggregators, and values-only files pass. The
  # single codified exemption (shared/errors.rb, the sealed error taxonomy)
  # lives in the scanner ALLOWLIST; adding to it is a constitutional
  # amendment.
  it 'enforces one constant per file, named after the file' do
    offenders = SpecSupport::Architecture::SingleConstantFileScanner.violations(lib_root)

    expect(offenders).to eq([]), <<~MSG
      Files must define a single root constant named after the file (constitution §III):
      #{offenders.join("\n")}
    MSG
  end
end
