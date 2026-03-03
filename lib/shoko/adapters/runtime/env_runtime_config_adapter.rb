# frozen_string_literal: true

require_relative '../../core/ports/outbound/runtime_config'

module Shoko
  module Adapters
    module Runtime
      # Reads process runtime configuration from environment variables once and
      # exposes typed values through the RuntimeConfig port.
      class EnvRuntimeConfigAdapter
        include Core::Ports::Outbound::RuntimeConfig

        DEFAULT_REXML_ENTITY_EXPANSION_LIMIT = 10_000
        DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT = 2_000_000
        DEFAULT_ZIP_MAX_ENTRY_UNCOMPRESSED_BYTES = 64 * 1024 * 1024
        DEFAULT_ZIP_MAX_ENTRY_COMPRESSED_BYTES = 64 * 1024 * 1024
        DEFAULT_ZIP_MAX_TOTAL_UNCOMPRESSED_BYTES = 256 * 1024 * 1024

        def initialize(env: ENV)
          @skip_progress_overlay = env_flag(env, 'SHOKO_SKIP_PROGRESS_OVERLAY')
          @dictionary_backend_override = env_value(env, 'SHOKO_DICTIONARY')
          @rexml_entity_expansion_limit = env_positive_integer(
            env,
            'SHOKO_REXML_ENTITY_LIMIT',
            fallback: DEFAULT_REXML_ENTITY_EXPANSION_LIMIT
          )
          @rexml_entity_expansion_text_limit = env_positive_integer(
            env,
            'SHOKO_REXML_TEXT_LIMIT',
            fallback: DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT
          )
          @debug_perf_enabled = env_flag(env, 'DEBUG_PERF')
          @text_metrics_cache_disabled = env_flag(env, 'SHOKO_DISABLE_TEXT_METRICS_CACHE')
          @wrap_plain_text_cache_disabled = env_flag(env, 'SHOKO_DISABLE_WRAP_PLAIN_TEXT_CACHE')
          @text_metrics_ascii_fast_path_disabled = env_flag(env, 'SHOKO_DISABLE_TEXT_METRICS_ASCII_FAST_PATH')
          @wrapping_window_range_cache_disabled = env_flag(env, 'SHOKO_DISABLE_WINDOW_RANGE_CACHE')
          @fast_manifest_lookup_disabled = env_flag(env, 'SHOKO_DISABLE_FAST_MANIFEST_LOOKUP')
          @manifest_rows_cache_disabled = env_flag(env, 'SHOKO_DISABLE_MANIFEST_ROWS_CACHE')
          @line_assembler_tokenize_cache_disabled = env_flag(env, 'SHOKO_DISABLE_LINE_ASSEMBLER_TOKENIZE_CACHE')
          @line_assembler_token_width_hints_disabled = env_flag(env, 'SHOKO_DISABLE_LINE_ASSEMBLER_TOKEN_WIDTH_HINTS')
          @fast_ascii_frame_write_disabled = env_flag(env, 'SHOKO_DISABLE_FAST_ASCII_FRAME_WRITE')
          @line_content_compose_cache_disabled = env_flag(env, 'SHOKO_DISABLE_LINE_CONTENT_COMPOSE_CACHE')
          @line_geometry_cell_cache_disabled = env_flag(env, 'SHOKO_DISABLE_LINE_GEOMETRY_CELL_CACHE')
          @debug_geometry_enabled = env_flag(env, 'SHOKO_DEBUG_GEOMETRY')
          @zip_max_entry_uncompressed_bytes = env_positive_integer(
            env,
            'SHOKO_ZIP_MAX_ENTRY_BYTES',
            fallback: DEFAULT_ZIP_MAX_ENTRY_UNCOMPRESSED_BYTES
          )
          @zip_max_entry_compressed_bytes = env_positive_integer(
            env,
            'SHOKO_ZIP_MAX_ENTRY_COMPRESSED_BYTES',
            fallback: DEFAULT_ZIP_MAX_ENTRY_COMPRESSED_BYTES
          )
          @zip_max_total_uncompressed_bytes = env_positive_integer(
            env,
            'SHOKO_ZIP_MAX_TOTAL_BYTES',
            fallback: DEFAULT_ZIP_MAX_TOTAL_UNCOMPRESSED_BYTES
          )
        end

        def skip_progress_overlay?
          @skip_progress_overlay
        end

        def dictionary_backend_override
          @dictionary_backend_override
        end

        def rexml_entity_expansion_limit
          @rexml_entity_expansion_limit
        end

        def rexml_entity_expansion_text_limit
          @rexml_entity_expansion_text_limit
        end

        def debug_perf_enabled?
          @debug_perf_enabled
        end

        def text_metrics_cache_disabled?
          @text_metrics_cache_disabled
        end

        def wrap_plain_text_cache_disabled?
          @wrap_plain_text_cache_disabled
        end

        def text_metrics_ascii_fast_path_disabled?
          @text_metrics_ascii_fast_path_disabled
        end

        def wrapping_window_range_cache_disabled?
          @wrapping_window_range_cache_disabled
        end

        def fast_manifest_lookup_disabled?
          @fast_manifest_lookup_disabled
        end

        def manifest_rows_cache_disabled?
          @manifest_rows_cache_disabled
        end

        def line_assembler_tokenize_cache_disabled?
          @line_assembler_tokenize_cache_disabled
        end

        def line_assembler_token_width_hints_disabled?
          @line_assembler_token_width_hints_disabled
        end

        def fast_ascii_frame_write_disabled?
          @fast_ascii_frame_write_disabled
        end

        def line_content_compose_cache_disabled?
          @line_content_compose_cache_disabled
        end

        def line_geometry_cell_cache_disabled?
          @line_geometry_cell_cache_disabled
        end

        def debug_geometry_enabled?
          @debug_geometry_enabled
        end

        def zip_max_entry_uncompressed_bytes
          @zip_max_entry_uncompressed_bytes
        end

        def zip_max_entry_compressed_bytes
          @zip_max_entry_compressed_bytes
        end

        def zip_max_total_uncompressed_bytes
          @zip_max_total_uncompressed_bytes
        end

        private

        def env_flag(env, key)
          env_value(env, key) == '1'
        end

        def env_value(env, key)
          raw = fetch_env(env, key)
          value = raw.to_s.strip.downcase
          value.empty? ? nil : value
        rescue Shoko::Error
          raise
        end

        def env_positive_integer(env, key, fallback:)
          raw = fetch_env(env, key)
          value = raw.to_s.strip
          return fallback if value.empty?

          parsed = value.to_i
          parsed.positive? ? parsed : fallback
        rescue Shoko::Error
          fallback
        end

        def fetch_env(env, key)
          env.fetch(key, nil)
        end
      end
    end
  end
end
