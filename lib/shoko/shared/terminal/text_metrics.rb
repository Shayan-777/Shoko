# frozen_string_literal: true

require_relative 'text_metrics/measurer'
require_relative 'text_metrics/runtime_controls'
require_relative 'text_metrics/truncator'
require_relative 'text_metrics/visible_length_cache'
require_relative 'text_metrics/wrap_plain_text_cache'
require_relative 'text_metrics/wrapper'

module Shoko
  module Shared
    module Terminal
      # Stable facade for measuring, truncating, and wrapping strings (with
      # ANSI support) in terminal cells. The work lives in collaborator
      # objects with distinct roles and state (R1/R3): RuntimeControls owns
      # runtime configuration and per-thread toggles, the two caches own
      # their memo state, Measurer owns measurement and text lexing, and
      # Truncator/Wrapper build on the Measurer. The facade wires them once
      # and keeps the public API and shared constants in one place.
      module TextMetrics
        TAB_SIZE = Measurer::TAB_SIZE
        CSI_REGEX = Measurer::CSI_REGEX
        ANSI_REGEX = Measurer::ANSI_REGEX
        TOKEN_REGEX = Measurer::TOKEN_REGEX
        DISPLAY_WIDTH = Measurer::DISPLAY_WIDTH

        CONTROLS = RuntimeControls.new
        VISIBLE_CACHE = VisibleLengthCache.new(controls: CONTROLS)
        WRAP_CACHE = WrapPlainTextCache.new(controls: CONTROLS)
        MEASURER = Measurer.new(controls: CONTROLS, cache: VISIBLE_CACHE)
        TRUNCATOR = Truncator.new(measurer: MEASURER)
        WRAPPER = Wrapper.new(measurer: MEASURER, cache: WRAP_CACHE)
        private_constant :CONTROLS, :VISIBLE_CACHE, :WRAP_CACHE, :MEASURER, :TRUNCATOR, :WRAPPER

        module_function

        # --- runtime controls -------------------------------------------------

        def with_runtime_config(config:, &)
          CONTROLS.with_runtime_config(config: config, &)
        end

        def configure_runtime_config!(runtime_config:)
          CONTROLS.configure_runtime_config!(runtime_config: runtime_config)
        end

        def with_ascii_fast_path(enabled:, &)
          CONTROLS.with_ascii_fast_path(enabled: enabled, &)
        end

        def with_visible_length_cache(enabled:, &)
          CONTROLS.with_visible_length_cache(enabled: enabled, &)
        end

        def with_wrap_plain_text_cache(enabled:, &)
          CONTROLS.with_wrap_plain_text_cache(enabled: enabled, &)
        end

        def clear_visible_length_cache
          VISIBLE_CACHE.clear!
        end

        def clear_wrap_plain_text_cache
          WRAP_CACHE.clear!
        end

        def visible_length_cache_enabled? = CONTROLS.visible_length_cache_enabled?

        def ascii_fast_path_enabled? = CONTROLS.ascii_fast_path_enabled?

        def wrap_plain_text_cache_enabled? = CONTROLS.wrap_plain_text_cache_enabled?

        # --- measurement ------------------------------------------------------

        def visible_length(text) = MEASURER.visible_length(text)

        def cell_data_for(text) = MEASURER.cell_data_for(text)

        def strip_ansi(text) = MEASURER.strip_ansi(text)

        def display_width_for(cluster) = MEASURER.display_width_for(cluster)

        def expand_tabs(text, tab_size: TAB_SIZE) = MEASURER.expand_tabs(text, tab_size: tab_size)

        # --- truncation and padding ------------------------------------------

        def truncate_to(text, width, start_column: 0)
          TRUNCATOR.truncate_to(text, width, start_column: start_column)
        end

        def pad_right(text, width, start_column: 0, pad: ' ')
          TRUNCATOR.pad_right(text, width, start_column: start_column, pad: pad)
        end

        def pad_left(text, width, start_column: 0, pad: ' ')
          TRUNCATOR.pad_left(text, width, start_column: start_column, pad: pad)
        end

        def pad_center(text, width, start_column: 0, pad: ' ')
          TRUNCATOR.pad_center(text, width, start_column: start_column, pad: pad)
        end

        # --- wrapping ---------------------------------------------------------

        def wrap_plain_text(line, width) = WRAPPER.wrap_plain_text(line, width)

        def wrap_cells(text, width, start_column: 0)
          WRAPPER.wrap_cells(text, width, start_column: start_column)
        end
      end
    end
  end
end
