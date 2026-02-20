# frozen_string_literal: true

module Shoko
  module Shared
    module Runtime
      # Safe default runtime configuration used when an explicit runtime config
      # instance is not injected by composition.
      class NullRuntimeConfig
        DEFAULT_REXML_ENTITY_EXPANSION_LIMIT = 10_000
        DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT = 2_000_000
        DEFAULT_ZIP_MAX_ENTRY_UNCOMPRESSED_BYTES = 64 * 1024 * 1024
        DEFAULT_ZIP_MAX_ENTRY_COMPRESSED_BYTES = 64 * 1024 * 1024
        DEFAULT_ZIP_MAX_TOTAL_UNCOMPRESSED_BYTES = 256 * 1024 * 1024

        class << self
          def instance
            @instance ||= new
          end
        end

        def skip_progress_overlay? = false
        def dictionary_backend_override = nil
        def rexml_entity_expansion_limit = DEFAULT_REXML_ENTITY_EXPANSION_LIMIT
        def rexml_entity_expansion_text_limit = DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT
        def debug_perf_enabled? = false
        def text_metrics_cache_disabled? = false
        def wrap_plain_text_cache_disabled? = false
        def text_metrics_ascii_fast_path_disabled? = false
        def wrapping_window_range_cache_disabled? = false
        def fast_manifest_lookup_disabled? = false
        def manifest_rows_cache_disabled? = false
        def line_assembler_tokenize_cache_disabled? = false
        def line_assembler_token_width_hints_disabled? = false
        def fast_ascii_frame_write_disabled? = false
        def line_content_compose_cache_disabled? = false
        def line_geometry_cell_cache_disabled? = false
        def debug_geometry_enabled? = false
        def zip_max_entry_uncompressed_bytes = DEFAULT_ZIP_MAX_ENTRY_UNCOMPRESSED_BYTES
        def zip_max_entry_compressed_bytes = DEFAULT_ZIP_MAX_ENTRY_COMPRESSED_BYTES
        def zip_max_total_uncompressed_bytes = DEFAULT_ZIP_MAX_TOTAL_UNCOMPRESSED_BYTES
      end
    end
  end
end
