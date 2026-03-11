# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter do
  it 'parses typed runtime config values from env-like input' do
    env = {
      'SHOKO_SKIP_PROGRESS_OVERLAY' => '1',
      'SHOKO_DICTIONARY' => 'SQLite',
      'SHOKO_LIBGEN_URL' => 'https://books.example',
      'SHOKO_REXML_ENTITY_LIMIT' => '123',
      'SHOKO_REXML_TEXT_LIMIT' => '456',
      'DEBUG_PERF' => '1',
      'SHOKO_DISABLE_TEXT_METRICS_CACHE' => '1',
      'SHOKO_DISABLE_WRAP_PLAIN_TEXT_CACHE' => '1',
      'SHOKO_DISABLE_TEXT_METRICS_ASCII_FAST_PATH' => '1',
      'SHOKO_DISABLE_WINDOW_RANGE_CACHE' => '1',
      'SHOKO_DISABLE_FAST_MANIFEST_LOOKUP' => '1',
      'SHOKO_DISABLE_MANIFEST_ROWS_CACHE' => '1',
      'SHOKO_DISABLE_LINE_ASSEMBLER_TOKENIZE_CACHE' => '1',
      'SHOKO_DISABLE_LINE_ASSEMBLER_TOKEN_WIDTH_HINTS' => '1',
      'SHOKO_DISABLE_FAST_ASCII_FRAME_WRITE' => '1',
      'SHOKO_DISABLE_LINE_CONTENT_COMPOSE_CACHE' => '1',
      'SHOKO_DISABLE_LINE_GEOMETRY_CELL_CACHE' => '1',
      'SHOKO_DEBUG_GEOMETRY' => '1',
    }

    config = described_class.new(env: env)

    expect(config.skip_progress_overlay?).to be(true)
    expect(config.dictionary_backend_override).to eq('sqlite')
    expect(config.libgen_base_url).to eq('https://books.example')
    expect(config.rexml_entity_expansion_limit).to eq(123)
    expect(config.rexml_entity_expansion_text_limit).to eq(456)
    expect(config.debug_perf_enabled?).to be(true)
    expect(config.text_metrics_cache_disabled?).to be(true)
    expect(config.wrap_plain_text_cache_disabled?).to be(true)
    expect(config.text_metrics_ascii_fast_path_disabled?).to be(true)
    expect(config.wrapping_window_range_cache_disabled?).to be(true)
    expect(config.fast_manifest_lookup_disabled?).to be(true)
    expect(config.manifest_rows_cache_disabled?).to be(true)
    expect(config.line_assembler_tokenize_cache_disabled?).to be(true)
    expect(config.line_assembler_token_width_hints_disabled?).to be(true)
    expect(config.fast_ascii_frame_write_disabled?).to be(true)
    expect(config.line_content_compose_cache_disabled?).to be(true)
    expect(config.line_geometry_cell_cache_disabled?).to be(true)
    expect(config.debug_geometry_enabled?).to be(true)
  end

  it 'falls back to defaults for invalid values' do
    env = {
      'SHOKO_SKIP_PROGRESS_OVERLAY' => '0',
      'SHOKO_REXML_ENTITY_LIMIT' => '-1',
      'SHOKO_REXML_TEXT_LIMIT' => 'abc',
    }

    config = described_class.new(env: env)

    expect(config.skip_progress_overlay?).to be(false)
    expect(config.dictionary_backend_override).to be_nil
    expect(config.libgen_base_url).to be_nil
    expect(config.rexml_entity_expansion_limit).to eq(
      Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter::DEFAULT_REXML_ENTITY_EXPANSION_LIMIT
    )
    expect(config.rexml_entity_expansion_text_limit).to eq(
      Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter::DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT
    )
    expect(config.debug_perf_enabled?).to be(false)
    expect(config.text_metrics_cache_disabled?).to be(false)
    expect(config.wrap_plain_text_cache_disabled?).to be(false)
    expect(config.text_metrics_ascii_fast_path_disabled?).to be(false)
    expect(config.wrapping_window_range_cache_disabled?).to be(false)
    expect(config.fast_manifest_lookup_disabled?).to be(false)
    expect(config.manifest_rows_cache_disabled?).to be(false)
    expect(config.line_assembler_tokenize_cache_disabled?).to be(false)
    expect(config.line_assembler_token_width_hints_disabled?).to be(false)
    expect(config.fast_ascii_frame_write_disabled?).to be(false)
    expect(config.line_content_compose_cache_disabled?).to be(false)
    expect(config.line_geometry_cell_cache_disabled?).to be(false)
    expect(config.debug_geometry_enabled?).to be(false)
  end
end
