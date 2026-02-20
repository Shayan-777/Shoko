# frozen_string_literal: true

require_relative '../../../../../core/services/toc_tree_service'

module Shoko
  module Presentation::Ui::Components
    module Sidebar
      # Formats entry titles.
      module EntryTitleFormatter
        def self.format(entry)
          text = entry.title || 'Untitled'
          entry.level.zero? ? text.upcase : text
        end
      end

      # Formats tree structure prefix for entries.
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

      # Calculates indentation for wrapped lines.
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

      # Builds continuation prefix from segments.
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

      # Builds tree prefix from segments.
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

      # Represents a single tree segment.
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

      # Analyzes tree structure relationships.
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

      # Analyzes sibling relationships.
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

      # Analyzes ancestor continuation.
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

      # Selects appropriate icon for entry.
      class IconSelector
        def self.select(full_entries, _entry, full_index, collapsed_set:, filter_active:)
          tree_service = Shoko::Core::Services::TocTreeService.instance
          return ' ' unless tree_service.entry_has_children?(full_entries, full_index)

          collapsed = !filter_active && collapsed_set.include?(full_index)
          collapsed ? '▶' : '▼'
        end
      end

      # Provides styling colors for entries.
      class EntryStyler
        include Presentation::Ui::Constants::Ui

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
