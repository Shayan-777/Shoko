# frozen_string_literal: true

require_relative '../../application/ports/outbound/runtime_config'

module Shoko
  module Adapters
    module Runtime
      # Reads process runtime configuration from environment variables once and
      # exposes typed values through the RuntimeConfig port.
      class EnvRuntimeConfigAdapter
        include Application::Ports::Outbound::RuntimeConfig

        DEFAULT_REXML_ENTITY_EXPANSION_LIMIT = 10_000
        DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT = 2_000_000
        DEFAULT_ZIP_MAX_ENTRY_UNCOMPRESSED_BYTES = 64 * 1024 * 1024
        DEFAULT_ZIP_MAX_ENTRY_COMPRESSED_BYTES = 64 * 1024 * 1024
        DEFAULT_ZIP_MAX_TOTAL_UNCOMPRESSED_BYTES = 256 * 1024 * 1024
        BooleanFlags = Data.define(
          :skip_progress_overlay,
          :debug_perf_enabled,
          :text_metrics_cache_disabled,
          :wrap_plain_text_cache_disabled,
          :text_metrics_ascii_fast_path_disabled,
          :wrapping_window_range_cache_disabled,
          :fast_manifest_lookup_disabled,
          :manifest_rows_cache_disabled,
          :line_assembler_tokenize_cache_disabled,
          :line_assembler_token_width_hints_disabled,
          :fast_ascii_frame_write_disabled,
          :line_content_compose_cache_disabled,
          :line_geometry_cell_cache_disabled,
          :debug_geometry_enabled
        )
        RuntimeValues = Data.define(
          :dictionary_backend_override,
          :libgen_base_url,
          :rexml_entity_expansion_limit,
          :rexml_entity_expansion_text_limit
        )
        ZipLimits = Data.define(
          :zip_max_entry_uncompressed_bytes,
          :zip_max_entry_compressed_bytes,
          :zip_max_total_uncompressed_bytes
        )

        def initialize(env: ENV)
          @flags = build_flags(env)
          @runtime_values = build_runtime_values(env)
          @zip_limits = build_zip_limits(env)
        end

        def skip_progress_overlay? = @flags.skip_progress_overlay

        def dictionary_backend_override = @runtime_values.dictionary_backend_override

        def libgen_base_url = @runtime_values.libgen_base_url

        def rexml_entity_expansion_limit
          @runtime_values.rexml_entity_expansion_limit
        end

        def rexml_entity_expansion_text_limit
          @runtime_values.rexml_entity_expansion_text_limit
        end

        def zip_max_entry_uncompressed_bytes
          @zip_limits.zip_max_entry_uncompressed_bytes
        end

        def zip_max_entry_compressed_bytes
          @zip_limits.zip_max_entry_compressed_bytes
        end

        def zip_max_total_uncompressed_bytes
          @zip_limits.zip_max_total_uncompressed_bytes
        end

        def debug_perf_enabled?
          @flags.debug_perf_enabled
        end

        def text_metrics_cache_disabled?
          @flags.text_metrics_cache_disabled
        end

        def wrap_plain_text_cache_disabled?
          @flags.wrap_plain_text_cache_disabled
        end

        def text_metrics_ascii_fast_path_disabled?
          @flags.text_metrics_ascii_fast_path_disabled
        end

        def wrapping_window_range_cache_disabled?
          @flags.wrapping_window_range_cache_disabled
        end

        def fast_manifest_lookup_disabled?
          @flags.fast_manifest_lookup_disabled
        end

        def manifest_rows_cache_disabled?
          @flags.manifest_rows_cache_disabled
        end

        def line_assembler_tokenize_cache_disabled?
          @flags.line_assembler_tokenize_cache_disabled
        end

        def line_assembler_token_width_hints_disabled?
          @flags.line_assembler_token_width_hints_disabled
        end

        def fast_ascii_frame_write_disabled?
          @flags.fast_ascii_frame_write_disabled
        end

        def line_content_compose_cache_disabled?
          @flags.line_content_compose_cache_disabled
        end

        def line_geometry_cell_cache_disabled?
          @flags.line_geometry_cell_cache_disabled
        end

        def debug_geometry_enabled?
          @flags.debug_geometry_enabled
        end

        private

        def build_flags(env)
          BooleanFlags.new(**core_flags(env), **render_flags(env))
        end

        def build_runtime_values(env)
          RuntimeValues.new(
            dictionary_backend_override: env_value(env, 'SHOKO_DICTIONARY'),
            libgen_base_url: env_string(env, 'SHOKO_LIBGEN_URL'),
            rexml_entity_expansion_limit: env_positive_integer(
              env,
              'SHOKO_REXML_ENTITY_LIMIT',
              fallback: DEFAULT_REXML_ENTITY_EXPANSION_LIMIT
            ),
            rexml_entity_expansion_text_limit: env_positive_integer(
              env,
              'SHOKO_REXML_TEXT_LIMIT',
              fallback: DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT
            )
          )
        end

        def build_zip_limits(env)
          ZipLimits.new(**zip_limit_values(env))
        end

        def env_flag?(env, key)
          env_value(env, key) == '1'
        end

        def core_flags(env)
          {
            skip_progress_overlay: env_flag?(env, 'SHOKO_SKIP_PROGRESS_OVERLAY'),
            debug_perf_enabled: env_flag?(env, 'DEBUG_PERF'),
            text_metrics_cache_disabled: env_flag?(env, 'SHOKO_DISABLE_TEXT_METRICS_CACHE'),
            wrap_plain_text_cache_disabled: env_flag?(env, 'SHOKO_DISABLE_WRAP_PLAIN_TEXT_CACHE'),
            text_metrics_ascii_fast_path_disabled: env_flag?(env, 'SHOKO_DISABLE_TEXT_METRICS_ASCII_FAST_PATH'),
            wrapping_window_range_cache_disabled: env_flag?(env, 'SHOKO_DISABLE_WINDOW_RANGE_CACHE'),
          }
        end

        def render_flags(env)
          {
            fast_manifest_lookup_disabled: env_flag?(env, 'SHOKO_DISABLE_FAST_MANIFEST_LOOKUP'),
            manifest_rows_cache_disabled: env_flag?(env, 'SHOKO_DISABLE_MANIFEST_ROWS_CACHE'),
            line_assembler_tokenize_cache_disabled: env_flag?(env, 'SHOKO_DISABLE_LINE_ASSEMBLER_TOKENIZE_CACHE'),
            line_assembler_token_width_hints_disabled: env_flag?(env, 'SHOKO_DISABLE_LINE_ASSEMBLER_TOKEN_WIDTH_HINTS'),
            fast_ascii_frame_write_disabled: env_flag?(env, 'SHOKO_DISABLE_FAST_ASCII_FRAME_WRITE'),
            line_content_compose_cache_disabled: env_flag?(env, 'SHOKO_DISABLE_LINE_CONTENT_COMPOSE_CACHE'),
            line_geometry_cell_cache_disabled: env_flag?(env, 'SHOKO_DISABLE_LINE_GEOMETRY_CELL_CACHE'),
            debug_geometry_enabled: env_flag?(env, 'SHOKO_DEBUG_GEOMETRY'),
          }
        end

        def zip_limit_values(env)
          {
            **entry_zip_limits(env),
            **aggregate_zip_limits(env),
          }
        end

        def zip_limit(env, key, fallback)
          env_positive_integer(env, key, fallback: fallback)
        end

        def entry_zip_limits(env)
          {
            zip_max_entry_uncompressed_bytes: zip_limit(
              env,
              'SHOKO_ZIP_MAX_ENTRY_BYTES',
              DEFAULT_ZIP_MAX_ENTRY_UNCOMPRESSED_BYTES
            ),
            zip_max_entry_compressed_bytes: zip_limit(
              env,
              'SHOKO_ZIP_MAX_ENTRY_COMPRESSED_BYTES',
              DEFAULT_ZIP_MAX_ENTRY_COMPRESSED_BYTES
            ),
          }
        end

        def aggregate_zip_limits(env)
          {
            zip_max_total_uncompressed_bytes: zip_limit(
              env,
              'SHOKO_ZIP_MAX_TOTAL_BYTES',
              DEFAULT_ZIP_MAX_TOTAL_UNCOMPRESSED_BYTES
            ),
          }
        end

        def env_value(env, key)
          raw = fetch_env(env, key)
          value = raw.to_s.strip.downcase
          value.empty? ? nil : value
        end

        def env_string(env, key)
          raw = fetch_env(env, key)
          value = raw.to_s.strip
          value.empty? ? nil : value
        end

        def env_positive_integer(env, key, fallback:)
          raw = fetch_env(env, key)
          value = raw.to_s.strip
          return fallback if value.empty?

          parsed = value.to_i
          parsed.positive? ? parsed : fallback
        end

        def fetch_env(env, key)
          env.fetch(key, nil)
        end
      end
    end
  end
end
