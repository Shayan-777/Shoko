# frozen_string_literal: true

require 'set'

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Filters TOC entries based on search term.
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

      # Removes descendants of collapsed entries from the visible list.
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

      # Finds indices of matching entries and their ancestors.
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

      # Finds ancestor entries in tree structure.
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

      # Tracks level traversal for ancestor finding.
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

      # Provides hierarchy helpers for TOC entries.
      class EntryHierarchy
        def self.children?(entries, index)
          next_entry = entries[index + 1]
          return false unless next_entry

          next_entry.level > entries[index].level
        end
      end
    end
  end
end
