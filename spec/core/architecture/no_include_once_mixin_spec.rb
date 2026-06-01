# frozen_string_literal: true

require 'spec_helper'

# Enforces architecture constitution R1 ("hard zero" include-once mixins):
# a module mixed into exactly one host is forbidden. Such behavior must live as
# private methods on the host, or be promoted to a real collaborator object.
#
# This is a RATCHET. The pre-existing violations live in a baseline file and may
# only ever shrink:
#   * no NEW include-once mixin may appear (regression guard);
#   * every baseline entry that gets fixed must be deleted from the baseline,
#     so the list cannot go stale and progress stays visible.
# When the baseline reaches zero, R1 is fully and permanently enforced — at which
# point this spec collapses to a plain `expect(current).to be_empty`.
RSpec.describe 'No include-once mixins (constitution R1)' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:baseline_path) do
    File.join(root, 'spec', 'support', 'architecture', 'include_once_mixin_baseline.txt')
  end

  let(:current) do
    SpecSupport::Architecture::IncludeOnceMixinScanner.violations(lib_root)
  end

  let(:baseline) do
    File.readlines(baseline_path)
        .map(&:strip)
        .reject { |line| line.empty? || line.start_with?('#') }
        .sort
  end

  it 'introduces no new include-once mixins' do
    new_violations = current - baseline

    expect(new_violations).to be_empty, <<~MSG
      New include-once mixin(s) detected (constitution R1 — hard zero):

      #{new_violations.map { |p| "  - #{p}" }.join("\n")}

      A module included/prepended in exactly one place is forbidden. Inline it as
      private methods on its host, or promote it to a named collaborator object
      with >=2 callers / distinct state / its own unit test. See
      docs/architecture/constitution.md (Section II, R1).
    MSG
  end

  it 'keeps the baseline honest — fixed entries must be removed' do
    fixed = baseline - current

    expect(fixed).to be_empty, <<~MSG
      #{fixed.size} baseline entr(y/ies) are no longer include-once mixins. Delete
      them from spec/support/architecture/include_once_mixin_baseline.txt so the
      ratchet keeps tightening:

      #{fixed.map { |p| "  - #{p}" }.join("\n")}
    MSG
  end
end
