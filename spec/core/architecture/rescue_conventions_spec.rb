# frozen_string_literal: true

require 'spec_helper'

# Consolidated rescue/fallback conventions (constitution §V: one spec per rule *family*).
# Each example delegates to the shared RescueGuardrailAnalyzer. Replaces the former
# per-rule micro-specs: no_standard_error_rescue, no_rescue_exception, no_bare_string_raise,
# no_noop_reraise_rescue, no_overlapping_rescue_chains, no_rescue_numeric_default,
# no_implicit_null_runtime_config, no_stale_optional_resolution.
RSpec.describe 'Rescue and fallback conventions' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:analyzer) { SpecSupport::Architecture::RescueGuardrailAnalyzer }

  it 'requires rescue StandardError branches to fail fast with explicit translation/raising' do
    offenders = analyzer.standard_error_rescue_without_translation_offenders(lib_root:)
    expect(offenders).to eq([]),
                         "rescue StandardError must immediately raise/translate failures:\n#{offenders.join("\n")}"
  end

  it 'forbids rescue Exception in lib/shoko runtime sources' do
    offenders = analyzer.exception_rescue_offenders(lib_root:)
    expect(offenders).to eq([]), "rescue Exception is not allowed in runtime code:\n#{offenders.join("\n")}"
  end

  it 'forbids raise with string literals in lib/shoko runtime sources' do
    offenders = analyzer.bare_string_raise_offenders(lib_root:)
    expect(offenders).to eq([]), "raise with string literal is not allowed in runtime code:\n#{offenders.join("\n")}"
  end

  it 'forbids rescue branches that only re-raise without translation or context' do
    offenders = analyzer.no_op_reraise_rescue_offenders(lib_root:)
    expect(offenders).to eq([]), "No-op rescue re-raises must be removed:\n#{offenders.join("\n")}"
  end

  it 'forbids overlapping rescue classes after explicit re-raise in same rescue chain' do
    offenders = analyzer.overlapping_rescue_chain_offenders(lib_root:)
    expect(offenders).to eq([]),
                         "Overlapping rescue chains with explicit re-raise produce unreachable handlers:\n#{offenders.join("\n")}"
  end

  it 'forbids rescue branches that default to numeric literals' do
    offenders = analyzer.numeric_default_rescue_offenders(lib_root:)
    expect(offenders).to eq([]), "Rescue branches must not hide failures with numeric defaults:\n#{offenders.join("\n")}"
  end

  it 'forbids || NullRuntimeConfig.instance fallback expressions in runtime code' do
    offenders = analyzer.implicit_null_runtime_config_offenders(lib_root:)
    expect(offenders).to eq([]), "Implicit NullRuntimeConfig fallback expressions are not allowed:\n#{offenders.join("\n")}"
  end

  it 'forbids optional ternary resolution branches that resolve identically' do
    offenders = analyzer.stale_optional_resolution_offenders(lib_root:)
    expect(offenders).to eq([]),
                         "Optional resolution scaffolding remains with identical branches:\n#{offenders.join("\n")}"
  end
end
