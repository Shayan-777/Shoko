# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# Enforces the POSITIVE half of constitution R1: "used by two or more call
# sites" earns a single home.
#
# Every other rule in the constitution has a scanner. This one did not, and the
# amendment log records the cost: four hand-run consolidation sweeps
# (2026-07-10 popup primitives, 2026-07-11 "the symbolize sweep actually
# finished", 2026-07-11 width-blind word-wraps, 2026-07-11 scrollbar/
# ensure-visible stragglers), each announcing that the previous one had missed
# cases. An unenforced rule is re-litigated forever; an enforced one converges.
#
# A violation is one method body appearing, identical after normalization, in
# two or more FILES. Same-file repetition is out of scope — within one class it
# is usually a deliberate pair of small accessors, and R1 is about behavior
# fragmented across homes.
RSpec.describe 'No duplicate implementations (constitution R1)' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:scanner) { SpecSupport::Architecture::DuplicateImplementationScanner }

  # NO ALLOWLIST. Every duplicate above the significance floor was consolidated
  # on 2026-07-26; a new one is a defect, not an entry to be added here.
  it 'forbids the same method body in two or more files' do
    offenders = scanner.violations(lib_root)

    expect(offenders).to eq([]), <<~MSG
      Duplicated implementation(s) detected (constitution R1 — a unit of
      behavior used by two or more call sites earns ONE home).

      Give the behavior a single owner: a shared module/collaborator when the
      concept is genuinely shared, the base class when siblings need it, or the
      type that already owns the concept. Do NOT satisfy this rule by adding a
      one-line delegator in each file — that moves the duplication, it does not
      remove it.

      #{offenders.map { |entry| "  - #{entry}" }.join("\n")}
    MSG
  end

  describe 'scanner parsing (Ripper-backed)' do
    def bodies(source)
      SpecSupport::Architecture::DuplicateImplementationScanner::MethodBodyExtractor.extract(source)
    end

    def tokens_for(source, name)
      bodies(source).find { |method| method.name == name }.tokens
    end

    it 'sees the whole body past a block-form if/unless' do
      source = <<~RUBY
        def guarded(value)
          unless value.is_a?(String)
            raise ArgumentError, 'bad'
          end

          tail_work(value)
        end
      RUBY

      expect(tokens_for(source, 'guarded')).to include('on_ident:tail_work')
    end

    it 'does not treat a trailing modifier if/unless as an opening block' do
      source = <<~RUBY
        def modified(value)
          return nil unless value
          work(value) if value.positive?
        end

        def sibling
          other
        end
      RUBY

      expect(bodies(source).map(&:name)).to eq(%w[modified sibling])
    end

    it 'ignores formatting, comments, and line breaks when comparing bodies' do
      compact = "def a(x)\n  x.to_s.strip # trim\nend\n"
      spread  = "def b(x)\n  # a different comment\n  x\n    .to_s\n    .strip\nend\n"

      expect(tokens_for(compact, 'a')).to eq(tokens_for(spread, 'b'))
    end

    it 'distinguishes bodies that differ in a literal' do
      expect(tokens_for("def a\n  limit(10)\nend\n", 'a'))
        .not_to eq(tokens_for("def b\n  limit(20)\nend\n", 'b'))
    end

    it 'handles endless method definitions without swallowing what follows' do
      source = <<~RUBY
        def short = compute(1, 2)

        def after(value)
          value
        end
      RUBY

      expect(bodies(source).map(&:name)).to eq(%w[short after])
    end

    it 'does not end a method at a nested def, case, or begin' do
      source = <<~RUBY
        def outer(value)
          case value
          when Integer then handled(value)
          else
            begin
              risky(value)
            rescue StandardError
              nil
            end
          end
          final_marker
        end
      RUBY

      expect(tokens_for(source, 'outer')).to include('on_ident:final_marker')
    end

    it 'reports only cross-file duplicates, not repetition inside one file' do
      Dir.mktmpdir do |dir|
        twice = <<~RUBY
          class Sample
            def first(value)
              value.to_s.strip.downcase.gsub(/\\s+/, ' ')
            end

            def second(value)
              value.to_s.strip.downcase.gsub(/\\s+/, ' ')
            end
          end
        RUBY
        File.write(File.join(dir, 'same_file.rb'), twice)

        expect(scanner.violations(dir)).to eq([])
      end
    end

    it 'reports a body duplicated across two files' do
      Dir.mktmpdir do |dir|
        body = <<~RUBY
          class Sample
            def normalize(value)
              text = value.to_s.strip
              return nil if text.empty?

              text.downcase.gsub(/\\s+/, ' ')
            end
          end
        RUBY
        File.write(File.join(dir, 'one.rb'), body)
        File.write(File.join(dir, 'two.rb'), body.sub('Sample', 'Other'))

        expect(scanner.violations(dir)).to contain_exactly(
          a_string_matching(/normalize .* one\.rb:\d+, two\.rb:\d+/)
        )
      end
    end

    it 'ignores bodies below the significance floor' do
      Dir.mktmpdir do |dir|
        trivial = "class Sample\n  def name\n    @name\n  end\nend\n"
        File.write(File.join(dir, 'one.rb'), trivial)
        File.write(File.join(dir, 'two.rb'), trivial.sub('Sample', 'Other'))

        expect(scanner.violations(dir)).to eq([])
      end
    end
  end
end
