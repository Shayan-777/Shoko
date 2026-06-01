# frozen_string_literal: true

require_relative '../unicode_display_width'
require_relative 'text_metrics/runtime_controls'
require_relative 'text_metrics/caching'
require_relative 'text_metrics/measurement'
require_relative 'text_metrics/truncation'
require_relative 'text_metrics/wrapping'

module Shoko
  module Shared
    module Terminal
      # Utility helpers for measuring and truncating strings (with ANSI support)
      # while respecting grapheme clusters and terminal cell widths.
      module TextMetrics
        DISPLAY_WIDTH = ->(str) { Shoko::Shared::UnicodeDisplayWidth.width(str) }
        TAB_SIZE = 4
        CSI_REGEX = %r{\e\[[0-?]*[ -/]*[@-~]}
        ANSI_REGEX = CSI_REGEX
        TOKEN_REGEX = /#{CSI_REGEX}|\X/m
        VISIBLE_LENGTH_CACHE_LIMIT = 20_000
        VISIBLE_LENGTH_CACHEABLE_BYTES = 256
        VISIBLE_LENGTH_CACHE_KEY = :shoko_visible_length_cache
        VISIBLE_LENGTH_CACHE_ENABLED_KEY = :shoko_visible_length_cache_enabled
        WRAP_PLAIN_TEXT_CACHE_LIMIT = 2_000
        WRAP_PLAIN_TEXT_CACHEABLE_BYTES = 2_048
        WRAP_PLAIN_TEXT_CACHE_KEY = :shoko_wrap_plain_text_cache
        WRAP_PLAIN_TEXT_CACHE_ORDER_KEY = :shoko_wrap_plain_text_cache_order
        WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY = :shoko_wrap_plain_text_cache_enabled
        ASCII_FAST_PATH_ENABLED_KEY = :shoko_text_metrics_ascii_fast_path_enabled
        RUNTIME_CONFIG_KEY = :shoko_text_metrics_runtime_config

        extend RuntimeControls
        extend Caching
        extend Measurement
        extend Truncation
        extend Wrapping

        private_class_method :runtime_config,
                             :cached_visible_length,
                             :cached_wrap_plain_text,
                             :visible_length_cache_for,
                             :cacheable_visible_length_input?,
                             :cache_visible_length,
                             :wrap_plain_text_cache_for,
                             :cacheable_wrap_plain_text_input?,
                             :cache_wrap_plain_text,
                             :measured_visible_length,
                             :append_cell_data,
                             :visible_length_ascii,
                             :fast_ascii_truncate_candidate?,
                             :truncated_ascii_fast_path?,
                             :truncated_ascii_fast_path,
                             :compute_wrapped_plain_text,
                             :append_plain_wrap_word,
                             :append_oversized_plain_word,
                             :start_plain_wrap_word,
                             :plain_wrap_word_fits?,
                             :append_fitting_plain_word,
                             :push_plain_wrap_line,
                             :reset_plain_wrap_line,
                             :finalize_plain_wrap,
                             :truncation_passthrough?,
                             :truncate_tokens,
                             :append_truncated_token,
                             :append_ansi_token,
                             :append_tab_token,
                             :append_newline_token,
                             :append_visible_token,
                             :advance_truncation_state,
                             :pad_text,
                             :apply_padding,
                             :process_wrap_cell_cluster,
                             :wrap_cell_newline,
                             :wrap_cell_tab,
                             :wrap_cell_space,
                             :append_wrap_cell_cluster,
                             :wrap_cell_line_if_needed,
                             :reset_cell_wrap_line,
                             :finalize_cell_wrap
      end
    end
  end
end
