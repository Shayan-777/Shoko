# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for process-level runtime configuration.
        # Implementations adapt environment variables or other runtime sources.
        module RuntimeConfig
          # The contract states what conformance means, so every adapter that
          # accepts a runtime config checks it the same way and reports it with
          # the same message.
          #
          # @raise [ArgumentError] when the object does not implement this port
          def self.validate!(runtime_config)
            return runtime_config if runtime_config.is_a?(self)

            raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
          end

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

          # @return [Integer]
          def zip_max_entry_uncompressed_bytes
            raise NotImplementedError, "#{self.class} must implement #zip_max_entry_uncompressed_bytes"
          end

          # @return [Integer]
          def zip_max_entry_compressed_bytes
            raise NotImplementedError, "#{self.class} must implement #zip_max_entry_compressed_bytes"
          end

          # @return [Integer]
          def zip_max_total_uncompressed_bytes
            raise NotImplementedError, "#{self.class} must implement #zip_max_total_uncompressed_bytes"
          end

          # @return [String, nil]
          def libgen_base_url
            raise NotImplementedError, "#{self.class} must implement #libgen_base_url"
          end

          # @return [String, nil]
          def translate_base_url
            raise NotImplementedError, "#{self.class} must implement #translate_base_url"
          end
        end
      end
    end
  end
end
