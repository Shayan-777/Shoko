# frozen_string_literal: true

require_relative '../errors'
require_relative '../unicode_display_width'

module Shoko
  module Shared
    module Terminal
      # Utility helpers for measuring, truncating, and wrapping strings (with
      # ANSI support) while respecting grapheme clusters and terminal cell
      # widths. One flat module: R1 forbids splitting a single host's behavior
      # into single-use mixins (including `extend`ed ones), and R2 says length
      # alone never justifies a split.
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

        TruncationState = Struct.new(:current_width, :column)
        PlainWrapState = Struct.new(:lines, :current_line, :current_width)
        CellWrapState = Struct.new(:lines, :line, :line_width, :column, :start_column)
        private_constant :TruncationState, :PlainWrapState, :CellWrapState

        extend self

        # --- runtime controls -------------------------------------------------

        def with_runtime_config(config:)
          previous = Thread.current[RUNTIME_CONFIG_KEY]
          Thread.current[RUNTIME_CONFIG_KEY] = config if config
          yield
        ensure
          Thread.current[RUNTIME_CONFIG_KEY] = previous
        end

        def configure_runtime_config!(runtime_config:)
          @configured_runtime_config = runtime_config
        end

        def with_ascii_fast_path(enabled:)
          previous = Thread.current[ASCII_FAST_PATH_ENABLED_KEY]
          Thread.current[ASCII_FAST_PATH_ENABLED_KEY] = enabled ? true : false
          yield
        ensure
          Thread.current[ASCII_FAST_PATH_ENABLED_KEY] = previous
        end

        def clear_visible_length_cache
          Thread.current[VISIBLE_LENGTH_CACHE_KEY] = {}
        end

        def clear_wrap_plain_text_cache
          Thread.current[WRAP_PLAIN_TEXT_CACHE_KEY] = {}
          Thread.current[WRAP_PLAIN_TEXT_CACHE_ORDER_KEY] = []
        end

        def with_visible_length_cache(enabled:)
          previous = Thread.current[VISIBLE_LENGTH_CACHE_ENABLED_KEY]
          Thread.current[VISIBLE_LENGTH_CACHE_ENABLED_KEY] = enabled ? true : false
          yield
        ensure
          Thread.current[VISIBLE_LENGTH_CACHE_ENABLED_KEY] = previous
        end

        def with_wrap_plain_text_cache(enabled:)
          previous = Thread.current[WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY]
          Thread.current[WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY] = enabled ? true : false
          yield
        ensure
          Thread.current[WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY] = previous
        end

        def visible_length_cache_enabled?
          override = Thread.current[VISIBLE_LENGTH_CACHE_ENABLED_KEY]
          return override unless override.nil?

          !runtime_config.text_metrics_cache_disabled?
        end

        def ascii_fast_path_enabled?
          override = Thread.current[ASCII_FAST_PATH_ENABLED_KEY]
          return override unless override.nil?

          !runtime_config.text_metrics_ascii_fast_path_disabled?
        end

        def wrap_plain_text_cache_enabled?
          override = Thread.current[WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY]
          return override unless override.nil?

          !runtime_config.wrap_plain_text_cache_disabled?
        end

        # --- measurement ------------------------------------------------------

        def visible_length(text)
          source = text.to_s
          cached_visible_length(source) { measured_visible_length(source) }
        end

        def cell_data_for(text)
          expanded = expand_tabs(text.to_s)
          cells = []
          char_index = 0
          screen_x = 0

          expanded.each_grapheme_cluster do |cluster|
            char_index, screen_x = append_cell_data(cells, cluster, char_index, screen_x)
          end

          cells
        end

        def strip_ansi(text)
          text.to_s.gsub(ANSI_REGEX, '')
        end

        def display_width_for(cluster)
          return TAB_SIZE if cluster == "\t"
          return 0 if cluster == "\u00AD"

          width = DISPLAY_WIDTH.call(cluster)
          width = 1 if width <= 0 && !cluster.empty?
          width
        rescue Shoko::Error
          cluster.length
        end

        def expand_tabs(text, tab_size: TAB_SIZE)
          column = 0
          buffer = +''

          text.to_s.each_grapheme_cluster do |cluster|
            if cluster == "\t"
              spaces = tab_size - (column % tab_size)
              buffer << (' ' * spaces)
              column += spaces
            else
              buffer << cluster
              column += display_width_for(cluster)
            end
          end

          buffer
        end

        # --- truncation and padding ------------------------------------------

        def truncate_to(text, width, start_column: 0)
          max_width = width.to_i
          return '' if max_width <= 0

          str = text.to_s
          return '' if str.empty?
          return truncated_ascii_fast_path(str, max_width) if truncated_ascii_fast_path?(str, max_width)
          return str if truncation_passthrough?(str, max_width)

          truncate_tokens(str, max_width, start_column.to_i)
        end

        def pad_right(text, width, start_column: 0, pad: ' ')
          pad_text(:right, text, width, start_column: start_column, pad: pad)
        end

        def pad_left(text, width, start_column: 0, pad: ' ')
          pad_text(:left, text, width, start_column: start_column, pad: pad)
        end

        def pad_center(text, width, start_column: 0, pad: ' ')
          pad_text(:center, text, width, start_column: start_column, pad: pad)
        end

        # --- wrapping ---------------------------------------------------------

        def wrap_plain_text(line, width)
          source = line.to_s
          width_i = width.to_i
          cached_wrap_plain_text(source, width_i) { compute_wrapped_plain_text(source, width_i) }
        end

        def wrap_cells(text, width, start_column: 0)
          max_width = width.to_i
          return [''] if max_width <= 0

          state = CellWrapState.new([], +'', 0, start_column.to_i, start_column.to_i)

          text.to_s.each_grapheme_cluster do |cluster|
            process_wrap_cell_cluster(state, cluster, max_width)
          end

          finalize_cell_wrap(state)
        end

        private

        def runtime_config
          config = Thread.current[RUNTIME_CONFIG_KEY]
          config ||= @configured_runtime_config
          return config if config

          raise Shoko::ConfigurationError, 'TextMetrics runtime_config is not configured'
        end

        # --- caching ----------------------------------------------------------

        def cached_visible_length(source)
          cache = visible_length_cache_for(source)
          return yield unless cache

          cached = cache[source]
          return cached unless cached.nil?

          width = yield
          cache_visible_length(cache, source, width)
          width
        end

        def cached_wrap_plain_text(source, width_i)
          cache = wrap_plain_text_cache_for(source)
          return yield unless cache

          key = [width_i, source]
          cached = cache[key]
          return cached unless cached.nil?

          wrapped = yield
          cache_wrap_plain_text(cache, source, width_i, wrapped)
          wrapped
        end

        def visible_length_cache_for(source)
          return nil unless visible_length_cache_enabled?
          return nil unless cacheable_visible_length_input?(source)

          Thread.current[VISIBLE_LENGTH_CACHE_KEY] ||= {}
        end

        def cacheable_visible_length_input?(source)
          source.to_s.bytesize <= VISIBLE_LENGTH_CACHEABLE_BYTES
        end

        def cache_visible_length(cache, source, width)
          key = source.frozen? ? source : source.dup.freeze
          cache[key] = width
          cache.shift while cache.length > VISIBLE_LENGTH_CACHE_LIMIT
        end

        def wrap_plain_text_cache_for(source)
          return nil unless wrap_plain_text_cache_enabled?
          return nil unless cacheable_wrap_plain_text_input?(source)

          Thread.current[WRAP_PLAIN_TEXT_CACHE_KEY] ||= {}
        end

        def cacheable_wrap_plain_text_input?(source)
          source.to_s.bytesize <= WRAP_PLAIN_TEXT_CACHEABLE_BYTES
        end

        def cache_wrap_plain_text(cache, source, width_i, wrapped)
          key_source = source.frozen? ? source : source.dup.freeze
          key = [width_i, key_source]
          order = Thread.current[WRAP_PLAIN_TEXT_CACHE_ORDER_KEY] ||= []

          unless cache.key?(key)
            order << key
            while order.length > WRAP_PLAIN_TEXT_CACHE_LIMIT
              oldest = order.shift
              cache.delete(oldest)
            end
          end

          cache[key] = wrapped.map { |line| line.frozen? ? line : line.dup.freeze }.freeze
        end

        # --- measurement internals -------------------------------------------

        def measured_visible_length(source)
          stripped = strip_ansi(source)
          return visible_length_ascii(stripped) if ascii_fast_path_enabled? && stripped.ascii_only?

          expanded = expand_tabs(stripped)
          expanded.each_grapheme_cluster.sum { |cluster| display_width_for(cluster) }
        end

        def append_cell_data(cells, cluster, char_index, screen_x)
          grapheme_length = cluster.length
          display_width = display_width_for(cluster)

          cells << {
            cluster: cluster,
            char_start: char_index,
            char_end: char_index + grapheme_length,
            display_width: display_width,
            screen_x: screen_x,
          }

          [char_index + grapheme_length, screen_x + display_width]
        end

        def visible_length_ascii(text)
          return text.bytesize unless text.include?("\t")

          width = 0
          column = 0

          text.each_byte do |byte|
            if byte == 9
              spaces = TAB_SIZE - (column % TAB_SIZE)
              width += spaces
              column += spaces
            else
              width += 1
              column += 1
            end
          end

          width
        end

        def fast_ascii_truncate_candidate?(str)
          return false unless str.ascii_only?
          return false if str.include?("\e")

          !(str.include?("\t") || str.include?("\n") || str.include?("\r"))
        end

        # --- truncation internals --------------------------------------------

        def truncated_ascii_fast_path?(str, max_width)
          ascii_fast_path_enabled? &&
            fast_ascii_truncate_candidate?(str) &&
            max_width < str.bytesize
        end

        def truncated_ascii_fast_path(str, max_width)
          str.byteslice(0, max_width).to_s
        end

        def truncation_passthrough?(str, max_width)
          return false if str.include?("\t") || str.include?("\n") || str.include?("\r")

          max_width >= visible_length(str)
        end

        def truncate_tokens(str, max_width, start_column)
          buffer = +''
          state = TruncationState.new(0, start_column)

          str.scan(TOKEN_REGEX).each do |token|
            append_truncated_token(buffer, token, max_width, state)
            break if state.current_width >= max_width
          end

          buffer
        end

        def append_truncated_token(buffer, token, max_width, state)
          return if state.current_width >= max_width
          return append_ansi_token(buffer, token) if token.start_with?("\e[")
          return if token == "\e"

          remaining = max_width - state.current_width
          case token
          when "\t"
            append_tab_token(buffer, remaining, state)
          when "\n", "\r"
            append_newline_token(buffer, remaining, state)
          else
            append_visible_token(buffer, token, remaining, state)
          end
        end

        def append_ansi_token(buffer, token)
          buffer << token
        end

        def append_tab_token(buffer, remaining, state)
          spaces = TAB_SIZE - (state.column % TAB_SIZE)
          take = [spaces, remaining].min
          buffer << (' ' * take)
          advance_truncation_state(state, take)
        end

        def append_newline_token(buffer, remaining, state)
          return if remaining < 1

          buffer << ' '
          advance_truncation_state(state, 1)
        end

        def append_visible_token(buffer, token, remaining, state)
          token_width = display_width_for(token)
          return if token_width > remaining

          buffer << token
          advance_truncation_state(state, token_width)
        end

        def advance_truncation_state(state, width)
          state.current_width += width
          state.column += width
        end

        def pad_text(mode, text, width, start_column:, pad:)
          max_width = width.to_i
          return '' if max_width <= 0

          clipped = truncate_to(text.to_s, max_width, start_column: start_column)
          pad_length = max_width - visible_length(clipped)
          return clipped unless pad_length.positive?

          apply_padding(mode, clipped, pad.to_s, pad_length)
        end

        def apply_padding(mode, clipped, pad, pad_length)
          case mode
          when :left
            (pad * pad_length) + clipped
          when :center
            left = pad_length / 2
            right = pad_length - left
            (pad * left) + clipped + (pad * right)
          else
            clipped + (pad * pad_length)
          end
        end

        # --- wrapping internals ----------------------------------------------

        def compute_wrapped_plain_text(source, width_i)
          normalized = expand_tabs(source)
          return [''] if normalized.empty?
          return [normalized] if width_i <= 0

          state = PlainWrapState.new([], +'', 0)
          normalized.split(/\s+/).each { |word| append_plain_wrap_word(state, word, width_i) }
          finalize_plain_wrap(state)
        end

        def append_plain_wrap_word(state, word, width_i)
          return if word.nil? || word.empty?

          word_width = visible_length(word)
          return append_oversized_plain_word(state, word, width_i) if word_width > width_i
          return start_plain_wrap_word(state, word, word_width) if state.current_width.zero?
          return append_fitting_plain_word(state, word, word_width) if plain_wrap_word_fits?(state, word_width, width_i)

          push_plain_wrap_line(state)
          start_plain_wrap_word(state, word, word_width)
        end

        def append_oversized_plain_word(state, word, width_i)
          push_plain_wrap_line(state)
          chunks = wrap_cells(word, width_i)
          return if chunks.empty?

          state.lines.concat(chunks[0...-1])
          tail = chunks.last.to_s
          if tail.empty?
            reset_plain_wrap_line(state)
          else
            start_plain_wrap_word(state, tail, visible_length(tail))
          end
        end

        def start_plain_wrap_word(state, word, width)
          state.current_line.replace(word)
          state.current_width = width
        end

        def plain_wrap_word_fits?(state, word_width, width_i)
          state.current_width + 1 + word_width <= width_i
        end

        def append_fitting_plain_word(state, word, word_width)
          state.current_line << ' ' unless state.current_line.empty?
          state.current_line << word
          state.current_width += 1 + word_width
        end

        def push_plain_wrap_line(state)
          state.lines << state.current_line.dup unless state.current_line.empty?
          reset_plain_wrap_line(state)
        end

        def reset_plain_wrap_line(state)
          state.current_line.clear
          state.current_width = 0
        end

        def finalize_plain_wrap(state)
          state.lines << state.current_line.dup unless state.current_line.empty?
          state.lines.empty? ? [''] : state.lines
        end

        def process_wrap_cell_cluster(state, cluster, max_width)
          return wrap_cell_newline(state) if cluster == "\n"

          cluster = ' ' if cluster == "\r"
          return wrap_cell_tab(state, max_width) if cluster == "\t"

          append_wrap_cell_cluster(state, cluster, max_width)
        end

        def wrap_cell_newline(state)
          state.lines << state.line.dup
          reset_cell_wrap_line(state)
        end

        def wrap_cell_tab(state, max_width)
          spaces = TAB_SIZE - (state.column % TAB_SIZE)
          spaces.times do
            wrap_cell_space(state, max_width)
          end
        end

        def wrap_cell_space(state, max_width)
          wrap_cell_line_if_needed(state, 1, max_width)
          state.line << ' '
          state.line_width += 1
          state.column += 1
        end

        def append_wrap_cell_cluster(state, cluster, max_width)
          cluster_width = display_width_for(cluster)
          return if cluster_width <= 0 || cluster_width > max_width

          wrap_cell_line_if_needed(state, cluster_width, max_width)
          return if cluster_width > (max_width - state.line_width)

          state.line << cluster
          state.line_width += cluster_width
          state.column += cluster_width
        end

        def wrap_cell_line_if_needed(state, cluster_width, max_width)
          return unless state.line_width.positive? && (state.line_width + cluster_width > max_width)

          state.lines << state.line.dup
          reset_cell_wrap_line(state)
        end

        def reset_cell_wrap_line(state)
          state.line.clear
          state.line_width = 0
          state.column = state.start_column
        end

        def finalize_cell_wrap(state)
          state.lines << state.line.dup
          state.lines.empty? ? [''] : state.lines
        end
      end
    end
  end
end
