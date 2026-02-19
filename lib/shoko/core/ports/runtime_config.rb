# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for process-level runtime configuration.
      # Implementations adapt environment variables or other runtime sources.
      module RuntimeConfig
        # @return [Boolean]
        def skip_progress_overlay?
          raise NotImplementedError, "#{self.class} must implement #skip_progress_overlay?"
        end

        # @return [String, nil] e.g. "sqlite"
        def dictionary_backend_override
          raise NotImplementedError, "#{self.class} must implement #dictionary_backend_override"
        end

        # @return [Integer]
        def rexml_entity_expansion_limit
          raise NotImplementedError, "#{self.class} must implement #rexml_entity_expansion_limit"
        end

        # @return [Integer]
        def rexml_entity_expansion_text_limit
          raise NotImplementedError, "#{self.class} must implement #rexml_entity_expansion_text_limit"
        end

        # @return [Boolean]
        def debug_perf_enabled?
          raise NotImplementedError, "#{self.class} must implement #debug_perf_enabled?"
        end

        # @return [Boolean]
        def text_metrics_cache_disabled?
          raise NotImplementedError, "#{self.class} must implement #text_metrics_cache_disabled?"
        end

        # @return [Boolean]
        def wrap_plain_text_cache_disabled?
          raise NotImplementedError, "#{self.class} must implement #wrap_plain_text_cache_disabled?"
        end

        # @return [Boolean]
        def text_metrics_ascii_fast_path_disabled?
          raise NotImplementedError, "#{self.class} must implement #text_metrics_ascii_fast_path_disabled?"
        end

        # @return [Boolean]
        def wrapping_window_range_cache_disabled?
          raise NotImplementedError, "#{self.class} must implement #wrapping_window_range_cache_disabled?"
        end

        # @return [Boolean]
        def fast_manifest_lookup_disabled?
          raise NotImplementedError, "#{self.class} must implement #fast_manifest_lookup_disabled?"
        end

        # @return [Boolean]
        def manifest_rows_cache_disabled?
          raise NotImplementedError, "#{self.class} must implement #manifest_rows_cache_disabled?"
        end

        # @return [Boolean]
        def line_assembler_tokenize_cache_disabled?
          raise NotImplementedError, "#{self.class} must implement #line_assembler_tokenize_cache_disabled?"
        end

        # @return [Boolean]
        def line_assembler_token_width_hints_disabled?
          raise NotImplementedError, "#{self.class} must implement #line_assembler_token_width_hints_disabled?"
        end

        # @return [Boolean]
        def fast_ascii_frame_write_disabled?
          raise NotImplementedError, "#{self.class} must implement #fast_ascii_frame_write_disabled?"
        end

        # @return [Boolean]
        def line_content_compose_cache_disabled?
          raise NotImplementedError, "#{self.class} must implement #line_content_compose_cache_disabled?"
        end

        # @return [Boolean]
        def line_geometry_cell_cache_disabled?
          raise NotImplementedError, "#{self.class} must implement #line_geometry_cell_cache_disabled?"
        end

        # @return [Boolean]
        def debug_geometry_enabled?
          raise NotImplementedError, "#{self.class} must implement #debug_geometry_enabled?"
        end
      end
    end
  end
end
