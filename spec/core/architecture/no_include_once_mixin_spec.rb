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

  describe 'scanner parsing (Ripper-backed)' do
    def sites(source)
      SpecSupport::Architecture::MixinSiteExtractor.extract(source)[1]
    end

    def extraction(source)
      SpecSupport::Architecture::MixinSiteExtractor.extract(source)
    end

    it 'detects bare, parenthesized, multiline, multi-argument, and ::-anchored mixin sites' do
      source = <<~RUBY
        module Host
          include Alpha, Beta
          prepend(Gamma)
          extend(::Delta)
          include(
            Epsilon::Zeta
          )
        end
      RUBY

      extracted = sites(source)
      expect(extracted.map(&:const)).to eq(%w[Alpha Beta Gamma Delta Epsilon::Zeta])
      expect(extracted.map(&:top_level)).to eq([false, false, false, true, false])
      expect(extracted.map(&:nesting).uniq).to eq([['Host']])
    end

    it 'ignores extend self and exposes dynamic targets instead of silently losing them' do
      source = <<~RUBY
        module Host
          extend self
          include forwardable_thing
          prepend(*runtime_mixins)
        end
      RUBY

      _definitions, extracted, _aliases, dynamic = extraction(source)
      expect(extracted).to eq([])
      expect(dynamic.map(&:method)).to eq(%w[include prepend])
    end

    it 'expands literal splats and explicit send forms' do
      source = <<~RUBY
        module Host
          include(*[Alpha, Beta])
          send(:prepend, Gamma)
          public_send(:extend, Delta)
        end
      RUBY

      expect(sites(source).map { |site| [site.method, site.const] }).to eq(
        [['include', 'Alpha'], ['include', 'Beta'], ['prepend', 'Gamma'], ['extend', 'Delta']]
      )
    end

    it 'keeps arguments on both sides of dynamic and literal splats' do
      source = <<~RUBY
        module Host
          include(Alpha, *runtime_mixins, Beta)
          prepend(*[Gamma, Delta], Epsilon)
        end
      RUBY

      _definitions, extracted, _aliases, dynamic = extraction(source)
      expect(extracted.map(&:const)).to eq(%w[Alpha Beta Gamma Delta Epsilon])
      expect(dynamic.map(&:method)).to eq(['include'])
    end

    it 'sees mixin calls made through an explicit receiver' do
      source = <<~RUBY
        module Host
          self.include(Alpha)
          Host.prepend Beta
        end
      RUBY

      expect(sites(source).map { |site| [site.method, site.const] }).to eq(
        [['include', 'Alpha'], ['prepend', 'Beta']]
      )
    end

    it 'resolves constant aliases to their canonical definition' do
      source = <<~RUBY
        module Host
          Mixin = ::Shared::Mixin
          include Mixin
        end
      RUBY
      definitions, extracted, aliases, = extraction(source)
      definitions << SpecSupport::Architecture::MixinSiteExtractor::Definition.new(
        segments: %w[Shared Mixin], depth: 1
      )
      known = definitions.to_h { |definition| [definition.segments.join('::'), true] }

      expect(
        SpecSupport::Architecture::IncludeOnceMixinScanner.resolve(extracted.first, known, aliases)
      ).to eq('Shared::Mixin')
    end

    it 'resolves ::-anchored constants only at the top level' do
      scanner = SpecSupport::Architecture::IncludeOnceMixinScanner
      site = SpecSupport::Architecture::MixinSiteExtractor::Site.new(
        method: 'include', const: 'Alpha', top_level: true, nesting: %w[Shoko Host]
      )

      expect(scanner.resolve(site, { 'Shoko::Host::Alpha' => true })).to be_nil
      expect(scanner.resolve(site, { 'Alpha' => true })).to eq('Alpha')
    end
  end

  # R1 through the other door: reopening a class (or module) in a second file
  # to inject method definitions is an include-once mixin without the
  # `include` — the same fragment indirection, invisible to the include
  # scanner. A class's methods live in the one file named after it (§III);
  # a second file under the class's namespace may only define its own nested
  # collaborator constants. No allowlist.
  it 'forbids method-bearing class reopenings across files' do
    fragments = SpecSupport::Architecture::ClassReopeningScanner.violations(lib_root)

    expect(fragments).to eq([]), <<~MSG
      Class fragment(s) detected (constitution R1/R3 — methods split across
      files via reopening). Merge the fragment's methods into the host file
      (length is never a reason to split, R2), or promote the fragment to a
      real collaborator object:

      #{fragments.map { |p| "  - #{p}" }.join("\n")}
    MSG
  end
end
