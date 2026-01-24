# frozen_string_literal: true

require 'set'
require_relative '../../../terminal/text_metrics'
require_relative '../../../../../core/models/toc_entry'

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      SCROLLBAR_WIDTH = 1
      RIGHT_MARGIN = 2

      # Orchestrates rendering of all components
      class ComponentOrchestrator
        def initialize(context)
          @context = context
        end

        def render
          return EmptyStateRenderer.new(@context).render if @context.entries.empty?

          HeaderRenderer.new(@context).render
          FilterInputRenderer.new(@context).render if @context.filter_active?
          EntriesListRenderer.new(@context).render
          ScrollbarRenderer.new(@context).render
        end
      end

      EntriesCache = Struct.new(:full, :visible, :visible_indices, keyword_init: true)

      # Encapsulates all rendering context and state
      class RenderContext
        include Adapters::Output::Ui::Constants::UI

        attr_reader :surface, :bounds, :state, :document, :wrap_cache

        def initialize(surface, bounds, state, document, wrap_cache: nil, entries_cache: nil)
          @surface = surface
          @bounds = bounds
          @state = state
          @document = document
          @wrap_cache = wrap_cache || {}
          @entries_cache = entries_cache
        end

        def entries
          return @entries if @entries
          return cached_entries if @entries_cache

          @entries = EntriesCalculator.new(self).calculate
        end

        def selected_index
          @selected_index ||= SelectedIndexCalculator.new(entries).calculate
        end

        def filter_active?
          state.get(%i[reader sidebar_toc_filter_active])
        end

        def filter_text
          state.get(%i[reader sidebar_toc_filter]) || ''
        end

        def collapsed_indices
          raw = state.get(%i[reader sidebar_toc_collapsed])
          Array(raw).map(&:to_i)
        end

        def collapsed_set
          @collapsed_set ||= Set.new(collapsed_indices)
        end

        def collapse_enabled?
          !filter_active?
        end

        def metrics
          @metrics ||= calculate_metrics
        end

        def write(row, col, text)
          surface.write(bounds, row, col, text)
        end

        def scroll_metrics
          @scroll_metrics ||= EntriesScrollMetrics.new(self)
        end

        def entries_layout
          @entries_layout ||= EntriesListLayout.new(self)
        end

        private

        def cached_entries
          @entries = EntriesCollection.new(
            full: @entries_cache.full,
            visible: @entries_cache.visible,
            visible_indices: @entries_cache.visible_indices,
            selected_full_index: selected_full_index_for(@entries_cache.full)
          )
        end

        def selected_full_index_for(entries)
          raw_index = state.get(%i[reader sidebar_toc_selected]) || 0
          max_index = [entries.length - 1, 0].max
          raw_index.to_i.clamp(0, max_index)
        end

        def calculate_metrics
          Metrics.new(
            x: 1,
            y: 1,
            width: bounds.width,
            height: bounds.height
          )
        end
      end

      # Calculates the selected index in visible list
      class SelectedIndexCalculator
        def initialize(entries)
          @entries = entries
        end

        def calculate
          selected_entry = full_entries[selected_full_index]
          find_visible_index(selected_entry)
        end

        private

        def full_entries
          @entries.full
        end

        def visible_entries
          @entries.visible
        end

        def selected_full_index
          @entries.selected_full_index
        end

        def find_visible_index(selected_entry)
          return 0 unless selected_entry

          visible_entries.index(selected_entry) || 0
        end
      end

      # Calculates entries collection with filtering
      class EntriesCalculator
        def initialize(context)
          @context = context
        end

        def calculate
          full_entries = DocumentEntriesExtractor.new(@context.document).extract
          filtered = apply_filter(full_entries)
          index_map = build_index_map(full_entries)
          visible = apply_collapse(filtered, full_entries, index_map)
          visible_indices = visible.filter_map { |entry| index_map[entry] }

          EntriesCollection.new(
            full: full_entries,
            visible: visible,
            visible_indices: visible_indices,
            selected_full_index: calculate_selected_index(full_entries)
          )
        end

        private

        def apply_filter(entries)
          return entries unless @context.filter_active?

          EntryFilter.new(entries, @context.filter_text).filter
        end

        def apply_collapse(entries, full_entries, index_map)
          return entries unless @context.collapse_enabled?

          collapsed = @context.collapsed_set
          return entries if collapsed.empty?

          CollapsedEntriesFilter.new(entries, full_entries, index_map, collapsed).filter
        end

        def build_index_map(entries)
          hash = {}.compare_by_identity
          entries.each_with_index { |entry, idx| hash[entry] = idx }
          hash
        end

        def calculate_selected_index(entries)
          raw_index = @context.state.get(%i[reader sidebar_toc_selected]) || 0
          max_index = [entries.length - 1, 0].max
          raw_index.to_i.clamp(0, max_index)
        end
      end

      # Extracts entries from document
      class DocumentEntriesExtractor
        def initialize(document)
          @document = NullDocument.wrap(document)
        end

        def extract
          toc_entries = @document.toc_entries
          return toc_entries unless toc_entries.empty?

          create_fallback_entries
        end

        private

        def create_fallback_entries
          chapters = @document.chapters
          FallbackEntriesBuilder.build(chapters)
        end
      end

      # Null object pattern for missing documents
      class NullDocument
        EMPTY_ARRAY = [].freeze
        EMPTY_HASH = {}.freeze

        def self.wrap(document)
          return document if document

          new
        end

        def toc_entries
          EMPTY_ARRAY
        end

        def chapters
          EMPTY_ARRAY
        end

        def metadata
          EMPTY_HASH
        end

        def title
          nil
        end
      end

      # Builds fallback entries from chapters
      module FallbackEntriesBuilder
        def self.build(chapters)
          chapters.each_with_index.map do |chapter, idx|
            create_entry(chapter, idx)
          end
        end

        def self.create_entry(chapter, index)
          Core::Models::TOCEntry.new(
            title: chapter.title || "Chapter #{index + 1}",
            href: nil,
            level: 1,
            chapter_index: index,
            navigable: true
          )
        end
      end

      # Metrics for layout calculations
      Metrics = Struct.new(:x, :y, :width, :height, keyword_init: true)

      # Collection of entries with selection state
      class EntriesCollection
        attr_reader :full, :visible, :visible_indices, :selected_full_index

        def initialize(full:, visible:, visible_indices:, selected_full_index:)
          @full = full
          @visible = visible
          @visible_indices = visible_indices
          @selected_full_index = selected_full_index
        end

        def empty?
          visible.empty?
        end

        def count
          full.length
        end
      end

      # Resolves document from dependencies
      class DocumentResolver
        def initialize(dependencies)
          @dependencies = NullDependencies.wrap(dependencies)
        end

        def resolve
          @dependencies.resolve(:document)
        end
      end

      # Null object for dependencies
      class NullDependencies
        def self.wrap(dependencies)
          return dependencies if dependencies

          new
        end

        def resolve(_key)
          nil
        end
      end

      # Filters TOC entries based on search term
      class EntryFilter
        def initialize(entries, filter_text)
          @entries = entries
          @filter_text = filter_text.to_s.strip
        end

        def filter
          return @entries if @filter_text.empty?

          matching_indices = MatchingIndicesFinder.new(@entries, @filter_text).find
          return [] if matching_indices.empty?

          select_matching_entries(matching_indices)
        end

        private

        def select_matching_entries(matching_indices)
          @entries.select.with_index { |_, idx| matching_indices.include?(idx) }
        end
      end

      # Removes descendants of collapsed entries from the visible list
      class CollapsedEntriesFilter
        def initialize(entries, full_entries, index_map, collapsed)
          @entries = entries
          @full_entries = full_entries
          @index_map = index_map
          @collapsed = collapsed
        end

        def filter
          visible = []
          skip_levels = []

          @entries.each do |entry|
            level = entry.level
            skip_levels.pop while skip_levels.any? && level <= skip_levels.last
            next if skip_levels.any?

            visible << entry
            full_index = @index_map[entry]
            next unless full_index
            next unless @collapsed.include?(full_index)
            next unless EntryHierarchy.children?(@full_entries, full_index)

            skip_levels << level
          end

          visible
        end
      end

      # Finds indices of matching entries and their ancestors
      class MatchingIndicesFinder
        def initialize(entries, filter_text)
          @entries = entries
          @filter_text = filter_text.downcase
        end

        def find
          required = Set.new
          find_matches(required)
          required
        end

        private

        def find_matches(required)
          @entries.each_with_index do |entry, idx|
            next unless entry_matches?(entry)

            required << idx
            add_ancestor_indices(idx, required)
          end
        end

        def entry_matches?(entry)
          entry.title.to_s.downcase.include?(@filter_text)
        end

        def add_ancestor_indices(start_idx, required)
          ancestor_finder = AncestorFinder.new(@entries, start_idx)
          ancestor_finder.find_all.each { |idx| required << idx }
        end
      end

      # Finds ancestor entries in tree structure
      class AncestorFinder
        def initialize(entries, start_idx)
          @entries = entries
          @start_idx = start_idx
          @start_level = entries[start_idx].level
        end

        def find_all
          ancestors = []
          tracker = LevelTracker.new(@start_level)

          scan_backwards do |idx|
            break if tracker.finished?

            process_ancestor(idx, tracker, ancestors)
          end

          ancestors
        end

        private

        def scan_backwards(&)
          (@start_idx - 1).downto(0, &)
        end

        def process_ancestor(idx, tracker, ancestors)
          ancestor_level = @entries[idx].level
          return unless tracker.ancestor?(ancestor_level)

          ancestors << idx
          tracker.descend_to(ancestor_level)
        end
      end

      # Tracks level traversal for ancestor finding
      class LevelTracker
        def initialize(start_level)
          @current_level = start_level
          @target_level = start_level - 1
        end

        def finished?
          @target_level.negative?
        end

        def ancestor?(level)
          level < @current_level
        end

        def descend_to(level)
          @current_level = level
          @target_level = level - 1
        end
      end

      # Renders empty state message
      class EmptyStateRenderer
        include Adapters::Output::Ui::Constants::UI

        MESSAGES = [
          'No chapters found',
          '',
          'Content may still be loading',
        ].freeze

        def initialize(context)
          @context = context
        end

        def render
          MESSAGES.each_with_index do |message, index|
            write_centered_message(message, index)
          end
        end

        private

        def write_centered_message(message, offset)
          x_pos = calculate_x_position(message)
          y_pos = start_y + offset
          styled_text = "#{COLOR_TEXT_DIM}#{message}#{Terminal::ANSI::RESET}"

          @context.write(y_pos, x_pos, styled_text)
        end

        def calculate_x_position(message)
          msg_width = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(message)
          [(@context.metrics.width - msg_width) / 2, 2].max
        end

        def start_y
          ((@context.metrics.height - MESSAGES.length) / 2) + 1
        end
      end

      # Renders header with title and entry count
      class HeaderRenderer
        include Adapters::Output::Ui::Constants::UI

        def initialize(context)
          @context = context
        end

        def render
          writer = HeaderWriter.new(@context)
          writer.write_title(title_content)
          writer.write_subtitle(subtitle_content) if should_show_subtitle?
          writer.write_divider

          @context.metrics.y + 2
        end

        private

        def title_content
          TitleExtractor.new(@context.document).extract
        end

        def subtitle_content
          SubtitleFormatter.new(@context.entries.count).format
        end

        def should_show_subtitle?
          subtitle_width = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(subtitle_content.plain)
          @context.metrics.width > subtitle_width + 2
        end
      end

      # Extracts and formats title from document
      class TitleExtractor
        DEFAULT_TITLE = 'CONTENTS'

        def initialize(document)
          @document = NullDocument.wrap(document)
        end

        def extract
          title = extract_title_text
          return default_content if title.empty?

          TitleContent.new(title.strip.upcase)
        end

        private

        def default_content
          @default_content ||= TitleContent.new(DEFAULT_TITLE)
        end

        def extract_title_text
          metadata_title = @document.metadata.fetch(:title, nil)
          metadata_title || @document.title || ''
        end
      end

      # Represents styled title content
      class TitleContent
        include Adapters::Output::Ui::Constants::UI

        attr_reader :plain

        def initialize(plain_text)
          @plain = plain_text
        end

        def styled
          "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_ACCENT}#{@plain}#{Terminal::ANSI::RESET}"
        end

        def width
          Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(@plain)
        end
      end

      # Formats subtitle with entry count
      class SubtitleFormatter
        def initialize(count)
          @count = count
        end

        def format
          SubtitleContent.new("#{@count} entries")
        end
      end

      # Represents styled subtitle content
      class SubtitleContent
        include Adapters::Output::Ui::Constants::UI

        attr_reader :plain

        def initialize(plain_text)
          @plain = plain_text
        end

        def styled
          "#{COLOR_TEXT_DIM}#{@plain}#{Terminal::ANSI::RESET}"
        end

        def width
          Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(@plain)
        end
      end

      # Writes header components to surface
      class HeaderWriter
        include Adapters::Output::Ui::Constants::UI

        def initialize(context)
          @context = context
          @metrics = context.metrics
          @last_title_width = 0
        end

        def write_title(title_content)
          @context.write(y_pos, x_pos + 1, title_content.styled)
          @last_title_width = title_content.width
        end

        def write_subtitle(subtitle_content)
          col = calculate_subtitle_column(subtitle_content)
          @context.write(y_pos, col, subtitle_content.styled)
        end

        def write_divider
          width = [@metrics.width - 2, 0].max
          divider = "#{COLOR_TEXT_DIM}#{'─' * width}#{Terminal::ANSI::RESET}"
          @context.write(y_pos + 1, x_pos + 1, divider)
          write_right_junction
        end

        private

        def calculate_subtitle_column(subtitle_content)
          min_col = x_pos + 1 + @last_title_width + 2
          right_col = x_pos + @metrics.width - subtitle_content.width - 1
          [right_col, min_col].max
        end

        def y_pos
          @metrics.y
        end

        def x_pos
          @metrics.x
        end

        def write_right_junction
          junction_col = x_pos + @metrics.width - 1
          return if junction_col < x_pos

          glyph = "#{COLOR_TEXT_DIM}┤#{Terminal::ANSI::RESET}"
          @context.write(y_pos + 1, junction_col, glyph)
        end
      end

      # Renders filter input field
      class FilterInputRenderer
        include Adapters::Output::Ui::Constants::UI

        def initialize(context)
          @context = context
        end

        def render
          write_input_line
          write_help_text
          start_y + 2
        end

        private

        def write_input_line
          prompt = "#{COLOR_TEXT_ACCENT}SEARCH ▸#{Terminal::ANSI::RESET} "
          @context.write(start_y, x_pos, "#{prompt}#{styled_input_text}")
        end

        def write_help_text
          help = "#{COLOR_TEXT_DIM}ESC cancel#{Terminal::ANSI::RESET}"
          @context.write(start_y + 1, x_pos, help)
        end

        def styled_input_text
          base = "#{COLOR_TEXT_PRIMARY}#{@context.filter_text}#{Terminal::ANSI::RESET}"
          cursor = @context.filter_active? ? "#{Terminal::ANSI::REVERSE} #{Terminal::ANSI::RESET}" : ''
          base + cursor
        end

        def start_y
          @context.metrics.y + 2
        end

        def x_pos
          @context.metrics.x + 1
        end
      end

      # Calculates layout information for TOC entries
      class EntriesListLayout
        attr_reader :content_start_y, :available_height, :max_width

        def initialize(context)
          @context = context
          @content_start_y = compute_content_start_y
          @available_height = compute_available_height
          @max_width = compute_max_width
        end

        def visible_items
          return [] if @context.entries.empty? || @available_height <= 0

          viewport = create_viewport_config
          VisibleItemsCalculator.new(
            @context.entries.visible,
            @context.entries.visible_indices,
            @context.selected_index,
            viewport,
            full_entries: @context.entries.full,
            collapsed_set: @context.collapsed_set,
            filter_active: @context.filter_active?,
            wrap_cache: @context.wrap_cache,
            line_index: line_index
          ).calculate
        end

        def item_at(row)
          visible_items.find do |item|
            row >= item.screen_y && row < (item.screen_y + item.visible_height)
          end
        end

        def total_height
          line_index.total_height
        end

        def line_index
          @line_index ||= LineIndex.new(@context.entries.visible, @max_width, @context.wrap_cache)
        end

        private

        def create_viewport_config
          ViewportConfig.new(
            start_y: @content_start_y,
            height: @available_height,
            max_width: @max_width
          )
        end

        def compute_content_start_y
          base = @context.metrics.y + 2
          base += 2 if @context.filter_active?
          base
        end

        def compute_available_height
          metrics = @context.metrics
          total = metrics.height - (@content_start_y - metrics.y)
          [total, 0].max
        end

        def compute_max_width
          [@context.metrics.width - 2 - SCROLLBAR_WIDTH - RIGHT_MARGIN, 0].max
        end
      end

      # Computes scroll metrics for TOC entries within the content viewport
      class EntriesScrollMetrics
        attr_reader :track_start_y, :track_height, :thumb_start_y, :thumb_height, :total_items,
                    :total_height, :viewport_height, :viewport_start, :max_start,
                    :scrollbar_start_col, :scrollbar_end_col, :visible_indices,
                    :selected_full_index, :selected_visible_index, :navigable_indices

        def initialize(context)
          @context = context
          @layout = context.entries_layout
          @visible_entries = context.entries.visible
          @visible_indices = context.entries.visible_indices
          @total_items = @visible_entries.length
          @total_height = @layout.total_height
          @viewport_height = @layout.available_height
          @scrollbar_end_col = context.metrics.width
          @scrollbar_start_col = [@scrollbar_end_col - SCROLLBAR_WIDTH + 1, 1].max
          @track_start_y = @layout.content_start_y
          @track_height = @layout.available_height
          @max_start = [@total_height - @viewport_height, 0].max
          @selected_visible_index = context.selected_index
          @selected_full_index = context.entries.selected_full_index
          @viewport_start = calculate_viewport_start
          @thumb_height = calculate_thumb_height
          @thumb_start_y = calculate_thumb_start
          @navigable_indices = build_navigable_indices
          @nav_positions = build_nav_positions
        end

        def scrollable?
          @track_height.positive? && @total_height.positive?
        end

        def absolute_scrollbar_start_col
          @context.bounds.x + @scrollbar_start_col - 1
        end

        def absolute_scrollbar_end_col
          @context.bounds.x + @scrollbar_end_col - 1
        end

        def absolute_track_start_y
          @context.bounds.y + @track_start_y - 1
        end

        def absolute_track_end_y
          absolute_track_start_y + @track_height - 1
        end

        def absolute_thumb_start_y
          @context.bounds.y + @thumb_start_y - 1
        end

        def hit_scrollbar?(abs_col, abs_row)
          return false unless scrollable?

          abs_col.between?(absolute_scrollbar_start_col, absolute_scrollbar_end_col) &&
            abs_row.between?(absolute_track_start_y, absolute_track_end_y)
        end

        def row_in_track?(abs_row)
          return false unless scrollable?

          abs_row.between?(absolute_track_start_y, absolute_track_end_y)
        end

        def hit_thumb?(abs_col, abs_row)
          return false unless hit_scrollbar?(abs_col, abs_row)
          return false unless @thumb_height.positive?

          abs_row.between?(absolute_thumb_start_y, absolute_thumb_start_y + @thumb_height - 1)
        end

        def full_index_for_abs_row(abs_row)
          full_index_for_row(abs_row - @context.bounds.y + 1)
        end

        def full_index_for_row(local_row)
          return nil unless scrollable?
          return nil if @visible_indices.empty?
          return @visible_indices.first if @max_start <= 0 || @track_height <= 1

          clamped = [local_row - @track_start_y, 0].max
          clamped = [clamped, @track_height - 1].min
          ratio = clamped.to_f / (@track_height - 1)
          viewport_start = (ratio * @max_start).round
          target_line = viewport_start + (@viewport_height / 2.0)
          target_index = @layout.line_index.entry_index_for_line(target_line) || 0
          @visible_indices[target_index]
        end

        def nav_position_for(full_index)
          @nav_positions[full_index]
        end

        private

        def calculate_viewport_start
          return 0 if @total_height <= @viewport_height || @viewport_height <= 0

          selected_index = @selected_visible_index.to_i.clamp(0, @visible_entries.length - 1)
          selected_offset = @layout.line_index.offset_for(selected_index)
          selected_height = @layout.line_index.height_for(selected_index)
          selected_center = selected_offset + (selected_height / 2.0)

          raw = selected_center - (@viewport_height / 2.0)
          raw = [raw, 0].max
          [raw.round, @max_start].min
        end

        def calculate_thumb_height
          return 0 unless scrollable?
          return @track_height if @max_start <= 0

          height = (@viewport_height.to_f / @total_height) * @track_height
          [height.round, 1].max
        end

        def calculate_thumb_start
          return @track_start_y unless scrollable?
          return @track_start_y if @max_start <= 0 || @track_height <= @thumb_height

          offset = ((@viewport_start.to_f / @max_start) * (@track_height - @thumb_height)).round
          @track_start_y + offset
        end

        def build_navigable_indices
          navigable = []
          @visible_entries.each_with_index do |entry, idx|
            navigable << @visible_indices[idx] if entry&.chapter_index
          end
          navigable.empty? ? @visible_indices.dup : navigable
        end

        def build_nav_positions
          positions = {}
          @navigable_indices.each_with_index { |idx, pos| positions[idx] = pos }
          positions
        end
      end

      # Renders list of TOC entries
      class EntriesListRenderer
        def initialize(context)
          @context = context
        end

        def render
          @context.entries_layout.visible_items.each { |item| render_entry_item(item) }
        end

        private

        def render_entry_item(item)
          EntryRenderer.new(@context, item).render
        end
      end

      # Renders a scrollbar at the right edge of the TOC content area
      class ScrollbarRenderer
        include Adapters::Output::Ui::Constants::UI

        TRACK_CHAR = '░'
        THUMB_CHAR = '█'

        def initialize(context)
          @context = context
        end

        def render
          metrics = @context.scroll_metrics
          return unless metrics.scrollable?

          draw_track(metrics)
          draw_thumb(metrics)
        end

        private

        def draw_track(metrics)
          track_end = metrics.track_start_y + metrics.track_height - 1
          line = "#{COLOR_TEXT_DIM}#{TRACK_CHAR * SCROLLBAR_WIDTH}#{Terminal::ANSI::RESET}"
          metrics.track_start_y.upto(track_end) do |row|
            @context.write(row, metrics.scrollbar_start_col, line)
          end
        end

        def draw_thumb(metrics)
          return unless metrics.thumb_height.positive?

          thumb_end = metrics.thumb_start_y + metrics.thumb_height - 1
          line = "#{COLOR_TEXT_ACCENT}#{THUMB_CHAR * SCROLLBAR_WIDTH}#{Terminal::ANSI::RESET}"
          metrics.thumb_start_y.upto(thumb_end) do |row|
            @context.write(row, metrics.scrollbar_start_col, line)
          end
        end
      end

      # Configuration for viewport
      ViewportConfig = Struct.new(:start_y, :height, :max_width, keyword_init: true)

      # Calculates wrapped lines and widths for entries
      class EntryLayoutHelper
        def self.wrap_lines(entry, max_width, wrap_cache)
          width = available_width(entry, max_width)
          return [''] if width <= 0

          cache = wrap_cache
          key = [entry.object_id, width]
          if cache
            cache[key] ||= Shoko::Adapters::Output::Terminal::TextMetrics.wrap_plain_text(formatted_title(entry), width)
          else
            Shoko::Adapters::Output::Terminal::TextMetrics.wrap_plain_text(formatted_title(entry), width)
          end
        end

        def self.line_count(entry, max_width, wrap_cache)
          wrap_lines(entry, max_width, wrap_cache).length
        end

        def self.available_width(entry, max_width)
          width = max_width - width_without_title(entry)
          [width, 0].max
        end

        def self.width_without_title(entry)
          level = entry.level.to_i
          level = 0 if level.negative?
          (level * 2) + 2
        end

        def self.formatted_title(entry)
          EntryTitleFormatter.format(entry)
        end

        private_class_method :available_width, :width_without_title, :formatted_title
      end

      # Precomputes line offsets for variable-height entries
      class LineIndex
        attr_reader :total_height

        def initialize(entries, max_width, wrap_cache)
          @offsets = []
          @heights = []
          total = 0

          entries.each do |entry|
            @offsets << total
            height = EntryLayoutHelper.line_count(entry, max_width, wrap_cache)
            @heights << height
            total += height
          end

          @total_height = total
        end

        def height_for(index)
          @heights[index] || 0
        end

        def offset_for(index)
          @offsets[index] || 0
        end

        def entry_index_for_line(line)
          return nil if @offsets.empty?
          return 0 if @total_height <= 0

          line = line.to_i
          line = 0 if line.negative?
          line = @total_height - 1 if line >= @total_height

          low = 0
          high = @offsets.length - 1
          while low <= high
            mid = (low + high) / 2
            if @offsets[mid] <= line
              return mid if mid == @offsets.length - 1 || @offsets[mid + 1] > line

              low = mid + 1
            else
              high = mid - 1
            end
          end

          0
        end
      end

      # Calculates which entries are visible in viewport
      class VisibleItemsCalculator
        def initialize(entries, visible_indices, selected_index, viewport, full_entries:,
                       collapsed_set:, filter_active:, wrap_cache:, line_index:)
          @entries = entries
          @visible_indices = visible_indices
          @selected_index = selected_index
          @viewport = viewport
          @full_entries = full_entries
          @collapsed_set = collapsed_set
          @filter_active = filter_active
          @wrap_cache = wrap_cache
          @line_index = line_index
        end

        def calculate
          return [] if @entries.empty? || @viewport.height <= 0
          return [] if @line_index.total_height <= 0

          viewport_start = viewport_start_line
          start_index = @line_index.entry_index_for_line(viewport_start) || 0
          start_offset = viewport_start - @line_index.offset_for(start_index)
          items = []
          remaining = @viewport.height
          screen_y = @viewport.start_y
          idx = start_index
          offset = start_offset

          while idx < @entries.length && remaining.positive?
            entry = @entries[idx]
            full_index = @visible_indices[idx]
            config = ItemConfig.new(
              item_entries: @entries,
              entry: entry,
              index: idx,
              full_index: full_index,
              selected_index: @selected_index,
              max_width: @viewport.max_width,
              full_entries: @full_entries,
              collapsed_set: @collapsed_set,
              filter_active: @filter_active,
              wrap_cache: @wrap_cache
            )
            item = VisibleEntryItem.new(config)
            height = item.height
            visible_height = [height - offset, remaining].min
            items << item.with_screen_position(screen_y, offset, visible_height)
            screen_y += visible_height
            remaining -= visible_height
            offset = 0
            idx += 1
          end

          items
        end

        private

        def viewport_start_line
          total_height = @line_index.total_height
          return 0 if total_height <= @viewport.height || @viewport.height <= 0

          selected_index = @selected_index.to_i.clamp(0, @entries.length - 1)
          selected_offset = @line_index.offset_for(selected_index)
          selected_height = @line_index.height_for(selected_index)
          selected_center = selected_offset + (selected_height / 2.0)

          raw_start = selected_center - (@viewport.height / 2.0)
          raw_start = [raw_start, 0].max
          max_start = [total_height - @viewport.height, 0].max
          [raw_start.round, max_start].min
        end
      end

      # Configuration for creating visible entry items
      ItemConfig = Struct.new(
        :item_entries, :entry, :index, :full_index, :selected_index, :max_width,
        :full_entries, :collapsed_set, :filter_active, :wrap_cache,
        keyword_init: true
      )

      # Represents a single entry item with rendering info
      class VisibleEntryItem
        attr_reader :entry, :index, :full_index, :max_width

        def initialize(config)
          @config = config
          @entry = config.entry
          @index = config.index
          @full_index = config.full_index
          @max_width = config.max_width
        end

        def with_screen_position(screen_y, start_offset, visible_height)
          PositionedEntryItem.new(self, screen_y, start_offset, visible_height)
        end

        def selected?
          index == @config.selected_index
        end

        def height
          wrapped_lines.length
        end

        def wrapped_lines
          @wrapped_lines ||= EntryLayoutHelper.wrap_lines(@entry, @max_width, @config.wrap_cache)
        end

        def components
          @components ||= EntryComponents.new(
            @config.item_entries,
            @entry,
            @index,
            full_entries: @config.full_entries,
            full_index: @config.full_index,
            collapsed_set: @config.collapsed_set,
            filter_active: @config.filter_active
          )
        end
      end

      # Item with screen position
      class PositionedEntryItem
        attr_reader :screen_y, :start_offset, :visible_height

        def initialize(item, screen_y, start_offset, visible_height)
          @item = item
          @screen_y = screen_y
          @start_offset = start_offset
          @visible_height = visible_height
        end

        def entry
          @item.entry
        end

        def index
          @item.index
        end

        def full_index
          @item.full_index
        end

        def max_width
          @item.max_width
        end

        def selected?
          @item.selected?
        end

        def height
          @visible_height
        end

        def wrapped_lines
          @item.wrapped_lines
        end

        def components
          @item.components
        end
      end

      # Renders a single TOC entry
      class EntryRenderer
        include Adapters::Output::Ui::Constants::UI

        def initialize(context, item)
          @context = context
          @item = item
        end

        def render
          render_lines
        end

        private

        def render_lines
          formatter = EntryFormatter.new(@item)
          lines = formatter.lines
          start = @item.start_offset
          visible = @item.visible_height
          lines_to_render = lines.slice(start, visible) || []

          lines_to_render.each_with_index do |line, offset|
            y_pos = @item.screen_y + offset
            write_gutter(y_pos)
            write_content(y_pos, line)
          end
        end

        def write_gutter(y_pos)
          gutter = gutter_symbol + Terminal::ANSI::RESET
          @context.write(y_pos, @context.metrics.x, gutter)
        end

        def gutter_symbol
          @item.selected? ? "#{COLOR_TEXT_ACCENT}│" : "#{COLOR_TEXT_DIM}│"
        end

        def write_content(y_pos, line)
          @context.write(y_pos, @context.metrics.x + 2, line)
        end
      end

      # Formats entry text with tree structure
      class EntryFormatter
        include Adapters::Output::Ui::Constants::UI

        def initialize(item)
          @item = item
          @components = item.components
        end

        def lines
          builder = EntryLineBuilder.new(@components, @item.wrapped_lines)
          @item.selected? ? builder.build_selected : builder.build
        end
      end

      # Builds multi-line entry strings
      class EntryLineBuilder
        include Adapters::Output::Ui::Constants::UI

        def initialize(components, wrapped_lines)
          @components = components
          @entry = components.entry
          @wrapped_lines = wrapped_lines
        end

        def build
          build_lines { |line, idx| format_line(line, idx) }
        end

        def build_selected
          build_lines { |line, idx| format_selected_line(line, idx) }
        end

        private

        def build_lines(&)
          @wrapped_lines.map.with_index(&)
        end

        def format_line(line, idx)
          idx.zero? ? format_first_line(line) : format_continuation_line(line)
        end

        def format_selected_line(line, idx)
          plain = idx.zero? ? plain_first_line(line) : plain_continuation_line(line)
          "#{Terminal::ANSI::BG_GREY}#{Terminal::ANSI::WHITE}#{plain}#{Terminal::ANSI::RESET}"
        end

        def format_first_line(line)
          parts = []
          prefix = @components.prefix
          parts << colorize(prefix, COLOR_TEXT_DIM) unless prefix.empty?

          if @components.icon_present?
            parts << colorize(@components.icon, EntryStyler.icon_color(@entry))
            parts << ' '
          end

          parts << colorize(line, EntryStyler.title_color(@entry))
          parts.join
        end

        def format_continuation_line(line)
          prefix = @components.continuation_prefix
          styled_prefix = prefix.empty? ? '' : colorize(prefix, COLOR_TEXT_DIM)
          "#{styled_prefix}#{colorize(line, EntryStyler.title_color(@entry))}"
        end

        def plain_first_line(line)
          spacer = @components.icon_present? ? ' ' : ''
          "#{@components.prefix}#{@components.icon}#{spacer}#{line}"
        end

        def plain_continuation_line(line)
          "#{@components.continuation_prefix}#{line}"
        end

        def colorize(text, color)
          return text if text.empty? || color.nil?

          "#{color}#{text}#{Terminal::ANSI::RESET}"
        end
      end

      # Calculates components of an entry (prefix, icon, title)
      class EntryComponents
        attr_reader :prefix, :icon, :title, :entry, :continuation_prefix

        def initialize(item_entries, entry, index, full_entries:, full_index:, collapsed_set:, filter_active:)
          @entry = entry
          @prefix = TreeFormatter.prefix(item_entries, index, entry.level)
          @icon = IconSelector.select(
            full_entries,
            entry,
            full_index,
            collapsed_set: collapsed_set,
            filter_active: filter_active
          )
          @title = EntryTitleFormatter.format(entry)
          @continuation_prefix = IndentCalculator.new(
            item_entries,
            index,
            entry.level,
            icon_present: icon_present?
          ).build
        end

        def icon_present?
          !@icon.empty?
        end

        def width_without_title
          prefix_width + icon_width + spacer_width
        end

        private

        def spacer_width
          icon_present? ? 1 : 0
        end

        def prefix_width
          Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(@prefix)
        end

        def icon_width
          Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(@icon)
        end
      end

      # Formats entry titles
      module EntryTitleFormatter
        def self.format(entry)
          text = entry.title || 'Untitled'
          entry.level.zero? ? text.upcase : text
        end
      end

      # Formats tree structure prefix for entries
      class TreeFormatter
        def self.prefix(item_entries, index, level)
          return '' if level <= 0

          PrefixBuilder.new(item_entries, index, level).build
        end

        def self.continuation_prefix(item_entries, index, level)
          return '' if level <= 0

          ContinuationPrefixBuilder.new(item_entries, index, level).build
        end
      end

      # Calculates indentation for wrapped lines
      class IndentCalculator
        def initialize(item_entries, index, level, icon_present:)
          @item_entries = item_entries
          @index = index
          @level = level
          @icon_present = icon_present
        end

        def build
          prefix = TreeFormatter.continuation_prefix(@item_entries, @index, @level)
          prefix + (@icon_present ? '  ' : '')
        end
      end

      # Builds continuation prefix from segments
      class ContinuationPrefixBuilder
        def initialize(item_entries, index, level)
          @item_entries = item_entries
          @index = index
          @level = level
        end

        def build
          (1..@level).map { |depth| segment_for_depth(depth) }.join
        end

        private

        def segment_for_depth(depth)
          TreeAnalyzer.ancestor_continues?(@item_entries, @index, depth) ? '│ ' : '  '
        end
      end

      # Builds tree prefix from segments
      class PrefixBuilder
        def initialize(item_entries, index, level)
          @item_entries = item_entries
          @index = index
          @level = level
        end

        def build
          (1..@level).map { |depth| segment_for_depth(depth) }.join
        end

        private

        def segment_for_depth(depth)
          TreeSegment.new(@item_entries, @index, depth, @level).format
        end
      end

      # Represents a single tree segment
      class TreeSegment
        def initialize(item_entries, index, depth, current_level)
          @item_entries = item_entries
          @index = index
          @depth = depth
          @current_level = current_level
        end

        def format
          at_current_level? ? branch_segment : continuation_segment
        end

        private

        def at_current_level?
          @depth == @current_level
        end

        def branch_segment
          TreeAnalyzer.last_child?(@item_entries, @index) ? '└─' : '├─'
        end

        def continuation_segment
          TreeAnalyzer.ancestor_continues?(@item_entries, @index, @depth) ? '│ ' : '  '
        end
      end

      # Analyzes tree structure relationships
      class TreeAnalyzer
        def self.last_child?(item_entries, index)
          analyzer = SiblingAnalyzer.new(item_entries, index)
          analyzer.last_child?
        end

        def self.ancestor_continues?(item_entries, index, depth)
          analyzer = AncestorContinuationAnalyzer.new(item_entries, index, depth)
          analyzer.continues?
        end
      end

      # Analyzes sibling relationships
      class SiblingAnalyzer
        def initialize(item_entries, index)
          @item_entries = item_entries
          @index = index
          @current_level = item_entries[index].level
        end

        def last_child?
          (@index + 1).upto(@item_entries.length - 1) do |next_index|
            next_level = @item_entries[next_index].level
            return false if next_level == @current_level
            return true if next_level < @current_level
          end

          true
        end
      end

      # Analyzes ancestor continuation
      class AncestorContinuationAnalyzer
        def initialize(item_entries, index, depth)
          @item_entries = item_entries
          @index = index
          @depth = depth
        end

        def continues?
          (@index + 1).upto(@item_entries.length - 1) do |next_index|
            next_level = @item_entries[next_index].level
            return true if next_level == @depth
            return false if next_level < @depth
          end

          false
        end
      end

      # Provides hierarchy helpers for TOC entries
      class EntryHierarchy
        def self.children?(entries, index)
          next_entry = entries[index + 1]
          return false unless next_entry

          next_entry.level > entries[index].level
        end
      end

      # Selects appropriate icon for entry
      class IconSelector
        def self.select(full_entries, _entry, full_index, collapsed_set:, filter_active:)
          return ' ' unless EntryHierarchy.children?(full_entries, full_index)

          collapsed = !filter_active && collapsed_set.include?(full_index)
          collapsed ? '▶' : '▼'
        end
      end

      # Provides styling colors for entries
      class EntryStyler
        include Adapters::Output::Ui::Constants::UI

        def self.icon_color(entry)
          ICON_COLORS[entry.level] || COLOR_TEXT_DIM
        end

        def self.title_color(entry)
          TITLE_COLORS[entry.level] || COLOR_TEXT_SECONDARY
        end

        ICON_COLORS = {
          0 => COLOR_TEXT_ACCENT,
          1 => COLOR_TEXT_SECONDARY,
        }.freeze

        TITLE_COLORS = {
          0 => "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_PRIMARY}",
          1 => COLOR_TEXT_PRIMARY,
        }.freeze
      end
    end
  end
end
