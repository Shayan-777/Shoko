# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# Enforces architecture constitution R1 ("hard zero" include-once mixins)
# through all three of its doors: a unit of behavior fused into exactly one
# host is forbidden whether it arrives by `include`/`prepend`/`extend`, by
# reopening the host class in a second file, or by being the superclass of a
# single subclass. Such behavior must live as private methods on the host, or
# be promoted to a real collaborator object.
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
      files via reopening). Merge the fragment's methods into the host file,
      or promote it to a real collaborator that owns a role/state/test seam
      under R2/R3; line count alone decides neither outcome:

      #{fragments.map { |p| "  - #{p}" }.join("\n")}
    MSG
  end

  # R1 through the third door: inheritance. A superclass with exactly one
  # subclass that is never used on its own — never constructed, never named as
  # a type — is an include-once mixin wearing a `<`. It exists only to be
  # completed by the one subclass, which reaches into its ivars and overrides
  # its no-op hooks; no caller ever sees the base type. Same fragmentation,
  # same costs, so the same rule. No allowlist: a base class earns its place
  # by having a second subclass or by being used in its own right.
  it 'forbids sole-subclass inheritance used as behavior fragmentation' do
    offenders = SpecSupport::Architecture::SoleSubclassScanner.violations(lib_root)

    expect(offenders).to eq([]), <<~MSG
      Sole-subclass base class(es) detected (constitution R1 — inheritance as
      fragmentation). Merge the base into its one subclass, or give the base a
      real reason to exist — a second subclass or use in its own right. Under
      R2, line count alone decides neither outcome:

      #{offenders.map { |p| "  - #{p}" }.join("\n")}
    MSG
  end

  describe 'sole-subclass scanner parsing (Ripper-backed)' do
    def edges(source)
      SpecSupport::Architecture::SoleSubclassScanner::InheritanceExtractor
        .extract(source)
        .map { |site| [site.subclass, site.superclass.const, site.superclass.nesting, site.superclass.top_level] }
    end

    it 'records nested, qualified, and ::-anchored superclass expressions' do
      source = <<~RUBY
        module Shoko
          module Adapters
            class Alpha < Beta; end
            class Gamma < Shoko::Core::Delta; end
            class Epsilon < ::Zeta; end
          end
        end
      RUBY

      expect(edges(source)).to eq(
        [
          ['Shoko::Adapters::Alpha', 'Beta', %w[Shoko Adapters], false],
          ['Shoko::Adapters::Gamma', 'Shoko::Core::Delta', %w[Shoko Adapters], false],
          ['Shoko::Adapters::Epsilon', 'Zeta', %w[Shoko Adapters], true],
        ]
      )
    end

    it 'ignores classes without a superclass and singleton class bodies' do
      source = <<~RUBY
        class Plain
          class << self
            def build = new
          end
        end
      RUBY

      expect(edges(source)).to eq([])
    end

    it 'counts a base as used when it is constructed or named as a type' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'sample.rb'), <<~RUBY)
          Built.new
          raise Raised, 'boom'
          begin; work; rescue Rescued => e; end
          value.is_a?(Checked)
          # Commented.new
        RUBY

        used = SpecSupport::Architecture::SoleSubclassScanner.independently_used_short_names(dir)

        expect(used.keys).to include('Built', 'Raised', 'Rescued', 'Checked')
        expect(used.keys).not_to include('Commented')
      end
    end
  end
end
