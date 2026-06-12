# frozen_string_literal: true

require 'spec_helper'

# Constitution §III: no `_support`, `_helper(s)`, `_coordinator`, `_dispatch`,
# `_mixin(s)`, `_actions` file suffix unless that word is a real role/domain
# concept. True Coordinator roles (pagination_coordinator, frame_coordinator,
# spellcheck_coordinator, selection_coordinator) are real patterns and not
# banned. The remaining banned-suffix files that predate this rule are held in
# a ratchet allowlist: nothing NEW may take these names, and entries leave the
# list as their hosts are renamed or folded (constitution amendment
# 2026-06-10).
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

  # Ratchet baseline as of 2026-06-10. Two are the constitution's documented
  # R1 allowlist holdouts awaiting the dictionary-wizard redesign; the rest
  # are pre-rule names that must not multiply.
  ALLOWLIST = %w[
    adapters/book_sources/epub/parser/opf/element_name_helpers.rb
    adapters/input/controllers/dependencies/dependency_record_mixins.rb
    adapters/input/controllers/dictionary/language_pair_support.rb
    adapters/input/controllers/dictionary/setup_flow_support.rb
    adapters/input/controllers/support/session_outcome_helpers.rb
    adapters/storage/json_cache_store/payload_helpers.rb
    adapters/support/lifecycle_helpers.rb
    adapters/ui/components/screens/annotation_rendering_helpers.rb
    adapters/ui/components/ui/annotation_markup/style_support.rb
    adapters/ui/components/ui/list_helpers.rb
    adapters/ui/rendering/line/config_helpers.rb
    adapters/ui/sessions/support/session_outcome_helpers.rb
    application/services/reader/navigation/context_helpers.rb
    core/services/progress_helper.rb
  ].freeze

  it 'forbids new files with banned grab-bag suffixes (ratchet)' do
    offenders = BANNED_SUFFIX_GLOBS.flat_map do |glob|
      Dir[File.join(lib_root, '**', glob)]
    end.map { |path| path.delete_prefix("#{lib_root}/") } - ALLOWLIST

    expect(offenders).to eq([]),
                         "New banned-suffix files (constitution §III — name the role, or keep private methods " \
                         "on the host):\n#{offenders.sort.join("\n")}"
  end

  it 'keeps the allowlist honest: every entry still exists' do
    stale = ALLOWLIST.reject { |rel| File.exist?(File.join(lib_root, rel)) }

    expect(stale).to eq([]),
                     "Allowlist entries no longer exist — remove them so the ratchet tightens:\n#{stale.join("\n")}"
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
end
