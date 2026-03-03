# frozen_string_literal: true

require 'set'
require_relative '../models/toc_entry'
require_relative '../ports/outbound/reader_document'
require_relative '../ports/outbound/reader_chapter'

module Shoko
  module Core
    module Services
      # Shared TOC tree operations used by controller navigation and UI rendering.
      class TocTreeService
        class << self
          def instance
            @instance ||= new
          end
        end

        def entries_for(document)
          return [] if document.nil?
          unless document.is_a?(Shoko::Core::Ports::Outbound::ReaderDocument)
            raise ArgumentError, 'document must implement Core::Ports::Outbound::ReaderDocument'
          end

          entries = Array(document.toc_entries)
          return entries unless entries.empty?

          chapter_count = [document.chapter_count.to_i, 0].max
          chapter_count.times.map do |idx|
            chapter = document.get_chapter(idx)
            next unless chapter
            unless chapter.is_a?(Shoko::Core::Ports::Outbound::ReaderChapter)
              raise ArgumentError, 'chapter must implement Core::Ports::Outbound::ReaderChapter'
            end

            title = chapter.title.to_s
            title = "Chapter #{idx + 1}" if title.strip.empty?
            Core::Models::TOCEntry.new(
              title: title,
              href: nil,
              level: 0,
              chapter_index: idx,
              navigable: true
            )
          end.compact
        end

        def entry_has_children?(entries, index)
          entries = Array(entries)
          return false unless index.is_a?(Integer) && index.between?(0, entries.length - 1)

          current_level = entries[index]&.level.to_i
          next_entry = entries[index + 1]
          next_entry && next_entry.level.to_i > current_level
        end

        def default_collapsed(entries)
          entries = Array(entries)
          entries.each_index.select { |idx| entry_has_children?(entries, idx) }
        end

        def normalize_collapsed(entries, raw)
          entries = Array(entries)
          return [] if entries.empty?

          max_index = entries.length - 1
          Array(raw).map(&:to_i).uniq.select do |idx|
            idx.between?(0, max_index) && entry_has_children?(entries, idx)
          end
        end

        def visible_indices(entries, collapsed: nil, filter_text: '', filter_active: false)
          entries = Array(entries)
          return [] if entries.empty?

          indices = if filter_active
                      filtered_indices(entries, filter_text.to_s)
                    else
                      entries.each_index.to_a
                    end

          return indices if filter_active

          apply_collapse(entries, indices, normalize_collapsed(entries, collapsed))
        end

        def ensure_visible_selection(entries, collapsed, current, filter_text: '', filter_active: false)
          entries = Array(entries)
          return 0 if entries.empty?

          current_i = current.to_i.clamp(0, entries.length - 1)
          visible = visible_indices(
            entries,
            collapsed: collapsed,
            filter_text: filter_text,
            filter_active: filter_active
          )
          return current_i if visible.include?(current_i)
          return visible.first || 0 if visible.empty?

          current_level = entries[current_i]&.level.to_i
          visible_set = visible.each_with_object({}) { |idx, memo| memo[idx] = true }
          (current_i - 1).downto(0) do |idx|
            next unless visible_set[idx]
            return idx if entries[idx].level.to_i < current_level
          end

          visible.reverse.find { |idx| idx < current_i } || visible.first
        end

        def navigable_indices(entries, collapsed, filter_text: '', filter_active: false)
          entries = Array(entries)
          visible = visible_indices(
            entries,
            collapsed: collapsed,
            filter_text: filter_text,
            filter_active: filter_active
          )
          indices = visible.select { |idx| !entries[idx]&.chapter_index.nil? }
          indices.empty? ? visible : indices
        end

        def toggle_collapsed(collapsed, index)
          list = Array(collapsed).map(&:to_i).uniq
          if list.include?(index)
            list - [index]
          else
            list + [index]
          end
        end

        def target_index(indices, current, delta)
          return current if delta.to_i.zero?

          if delta.to_i.positive?
            indices.find { |idx| idx > current } || indices.last || current
          else
            indices.reverse.find { |idx| idx < current } || indices.first || current
          end
        end

        def index_for_chapter(entries, chapter_index)
          Array(entries).find_index { |entry| entry&.chapter_index == chapter_index } || 0
        end

        private

        def filtered_indices(entries, filter_text)
          term = filter_text.to_s.strip.downcase
          return entries.each_index.to_a if term.empty?

          required = Set.new
          entries.each_with_index do |entry, idx|
            next unless entry.title.to_s.downcase.include?(term)

            required << idx
            add_ancestors(entries, idx, required)
          end
          required.to_a.sort
        end

        def add_ancestors(entries, start_idx, required)
          current_level = entries[start_idx].level.to_i
          (start_idx - 1).downto(0) do |idx|
            level = entries[idx].level.to_i
            next unless level < current_level

            required << idx
            current_level = level
            break if current_level <= 0
          end
        end

        def apply_collapse(entries, indices, collapsed)
          collapsed_set = collapsed.each_with_object({}) { |idx, memo| memo[idx] = true }
          visible = []
          skip_levels = []

          indices.each do |idx|
            level = entries[idx].level.to_i
            skip_levels.pop while skip_levels.any? && level <= skip_levels.last
            next if skip_levels.any?

            visible << idx
            next unless collapsed_set[idx]
            next unless entry_has_children?(entries, idx)

            skip_levels << level
          end

          visible
        end
      end
    end
  end
end
