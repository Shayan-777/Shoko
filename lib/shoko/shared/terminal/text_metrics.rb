# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      # Utility helpers for measuring and truncating strings (with ANSI support)
      # while respecting grapheme clusters and terminal cell widths.
      module TextMetrics
        require_relative '../unicode_display_width'
        require_relative '../runtime/null_runtime_config'
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

          module_function

        def with_runtime_config(config:)
          previous = Thread.current[RUNTIME_CONFIG_KEY]
          Thread.current[RUNTIME_CONFIG_KEY] = config if config
          yield
        ensure
          Thread.current[RUNTIME_CONFIG_KEY] = previous
        end

        def visible_length(text)
          source = text.to_s
          cache = visible_length_cache_for(source)
          unless cache.nil?
            cached = cache[source]
            return cached unless cached.nil?
          end

          stripped = strip_ansi(source)

          if ascii_fast_path_enabled? && stripped.ascii_only?
            width = visible_length_ascii(stripped)
            cache_visible_length(cache, source, width) if cache
            return width
          end

          # Fast path: directly compute display width without building cell data
          expanded = expand_tabs(stripped)
          width = 0
          expanded.each_grapheme_cluster do |cluster|
            width += display_width_for(cluster)
          end
          cache_visible_length(cache, source, width) if cache
          width
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

        def cell_data_for(text)
          expanded = expand_tabs(text.to_s)
          cells = []
          char_index = 0
          screen_x = 0

          expanded.each_grapheme_cluster do |cluster|
            grapheme_length = cluster.length
            display_width = display_width_for(cluster)

            cells << {
              cluster: cluster,
              char_start: char_index,
              char_end: char_index + grapheme_length,
              display_width: display_width,
              screen_x: screen_x,
            }

            char_index += grapheme_length
            screen_x += display_width
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
        rescue StandardError
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

        def wrap_plain_text(line, width)
          source = line.to_s
          width_i = width.to_i
          cache = wrap_plain_text_cache_for(source)
          unless cache.nil?
            cached = cache[[width_i, source]]
            return cached unless cached.nil?
          end

          normalized = expand_tabs(source)
          if normalized.empty?
            result = ['']
            cache_wrap_plain_text(cache, source, width_i, result) if cache
            return result
          end

          if width_i <= 0
            result = [normalized]
            cache_wrap_plain_text(cache, source, width_i, result) if cache
            return result
          end

          wrapped = []
          current_line = +''
          current_width = 0

          normalized.split(/\s+/).each do |word|
            next if word.nil? || word.empty?

            word_width = visible_length(word)

            if word_width > width_i
              wrapped << current_line.dup unless current_line.empty?
              current_line.clear
              current_width = 0

              chunks = wrap_cells(word, width_i)
              next if chunks.empty?

              wrapped.concat(chunks[0...-1])
              tail = chunks.last.to_s
              if tail.empty?
                current_line.clear
                current_width = 0
              else
                current_line.replace(tail)
                current_width = visible_length(tail)
              end
            elsif current_width.zero?
              current_line.replace(word)
              current_width = word_width
            elsif current_width + 1 + word_width <= width_i
              current_line << ' ' unless current_line.empty?
              current_line << word
              current_width += 1 + word_width
            else
              wrapped << current_line.dup unless current_line.empty?
              current_line.replace(word)
              current_width = word_width
            end
          end

          wrapped << current_line.dup unless current_line.empty?
          wrapped = [''] if wrapped.empty?
          cache_wrap_plain_text(cache, source, width_i, wrapped) if cache
          wrapped
        end

        def truncate_to(text, width, start_column: 0)
          max_width = width.to_i
          return '' if max_width <= 0

          str = text.to_s
          return '' if str.empty?

          if ascii_fast_path_enabled? && fast_ascii_truncate_candidate?(str)
            return str if max_width >= str.bytesize

            return str.byteslice(0, max_width).to_s
          end

          # Fast-path: preserve original when it already fits and contains no tab/newline.
          if !(str.include?("\t") || str.include?("\n") || str.include?("\r")) && (max_width >= visible_length(str))
            return str
          end

          buffer = +''
          current_width = 0
          column = start_column.to_i

          str.scan(TOKEN_REGEX).each do |token|
            if token.start_with?("\e[")
              buffer << token
              next
            end

            next if token == "\e"

            remaining = max_width - current_width
            break if remaining <= 0

            case token
            when "\t"
              spaces = TAB_SIZE - (column % TAB_SIZE)
              take = [spaces, remaining].min
              buffer << (' ' * take)
              current_width += take
              column += take
            when "\n", "\r"
              # Never allow newlines to affect terminal layout; treat as a space.
              break if remaining < 1

              buffer << ' '
              current_width += 1
              column += 1
            else
              token_width = display_width_for(token)
              break if token_width > remaining

              buffer << token
              current_width += token_width
              column += token_width
            end
          end

          buffer
        end

        def pad_right(text, width, start_column: 0, pad: ' ')
          w = width.to_i
          return '' if w <= 0

          clipped = truncate_to(text.to_s, w, start_column: start_column)
          pad_len = w - visible_length(clipped)
          pad_len.positive? ? (clipped + (pad.to_s * pad_len)) : clipped
        end

        def pad_left(text, width, start_column: 0, pad: ' ')
          w = width.to_i
          return '' if w <= 0

          clipped = truncate_to(text.to_s, w, start_column: start_column)
          pad_len = w - visible_length(clipped)
          pad_len.positive? ? ((pad.to_s * pad_len) + clipped) : clipped
        end

        def pad_center(text, width, start_column: 0, pad: ' ')
          w = width.to_i
          return '' if w <= 0

          clipped = truncate_to(text.to_s, w, start_column: start_column)
          pad_len = w - visible_length(clipped)
          return clipped unless pad_len.positive?

          left = pad_len / 2
          right = pad_len - left
          (pad.to_s * left) + clipped + (pad.to_s * right)
        end

        # Wraps text by terminal cell width without splitting grapheme clusters.
        # Preserves newlines and expands tabs relative to the provided start column.
        #
        # This is intended for UI text entry/display helpers (notes, dialogs),
        # not for paragraph-aware ebook formatting.
        def wrap_cells(text, width, start_column: 0)
          w = width.to_i
          return [''] if w <= 0

          lines = []
          line = +''
          line_width = 0
          column = start_column.to_i

          text.to_s.each_grapheme_cluster do |cluster|
            if cluster == "\n"
              lines << line.dup
              line.clear
              line_width = 0
              column = start_column.to_i
              next
            end

            cluster = ' ' if cluster == "\r"

            if cluster == "\t"
              spaces = TAB_SIZE - (column % TAB_SIZE)
              spaces.times do
                if line_width >= w
                  lines << line.dup
                  line.clear
                  line_width = 0
                  column = start_column.to_i
                end
                line << ' '
                line_width += 1
                column += 1
              end
              next
            end

            cw = display_width_for(cluster)
            next if cw <= 0
            next if cw > w

            if line_width.positive? && (line_width + cw > w)
              lines << line.dup
              line.clear
              line_width = 0
              column = start_column.to_i
            end

            break if cw > (w - line_width)

            line << cluster
            line_width += cw
            column += cw
          end

          lines << line.dup
          lines = [''] if lines.empty?
          lines
        end

        def visible_length_cache_for(source)
          return nil unless visible_length_cache_enabled?
          return nil unless cacheable_visible_length_input?(source)

          Thread.current[VISIBLE_LENGTH_CACHE_KEY] ||= {}
        end
        private_class_method :visible_length_cache_for

        def cacheable_visible_length_input?(source)
          source.to_s.bytesize <= VISIBLE_LENGTH_CACHEABLE_BYTES
        end
        private_class_method :cacheable_visible_length_input?

        def cache_visible_length(cache, source, width)
          key = source.frozen? ? source : source.dup.freeze
          cache[key] = width
          cache.shift while cache.length > VISIBLE_LENGTH_CACHE_LIMIT
        end
        private_class_method :cache_visible_length

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
        private_class_method :visible_length_ascii

        def fast_ascii_truncate_candidate?(str)
          return false unless str.ascii_only?
          return false if str.include?("\e")

          !(str.include?("\t") || str.include?("\n") || str.include?("\r"))
        end
        private_class_method :fast_ascii_truncate_candidate?

        def wrap_plain_text_cache_for(source)
          return nil unless wrap_plain_text_cache_enabled?
          return nil unless cacheable_wrap_plain_text_input?(source)

          Thread.current[WRAP_PLAIN_TEXT_CACHE_KEY] ||= {}
        end
        private_class_method :wrap_plain_text_cache_for

        def cacheable_wrap_plain_text_input?(source)
          source.to_s.bytesize <= WRAP_PLAIN_TEXT_CACHEABLE_BYTES
        end
        private_class_method :cacheable_wrap_plain_text_input?

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
        private_class_method :cache_wrap_plain_text

        def runtime_config
          Thread.current[RUNTIME_CONFIG_KEY] || Shoko::Shared::Runtime::NullRuntimeConfig.instance
        end
        private_class_method :runtime_config
      end
    end
  end
end
