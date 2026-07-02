# frozen_string_literal: true

require 'time'
require 'shoko/shared/text_sanitizer'
require 'shoko/shared/hash_normalizer'
require 'shoko/core/models/bookmark'
require 'shoko/core/models/bookmark_data'
require_relative 'base_file_store'

module Shoko
  module Adapters
    module Storage
      module Repositories
        module Storage
          # File-backed bookmark storage isolated under Domain.
          # Persists bookmarks to ${XDG_CONFIG_HOME:-~/.config}/shoko/bookmarks.json
          class BookmarkFileStore < BaseFileStore
            FILE_NAME = 'bookmarks.json'
            SCHEMA_VERSION = 1

            def add(bookmark_data)
              unless bookmark_data.is_a?(Shoko::Core::Models::BookmarkData)
                raise ArgumentError, 'bookmark_data must be BookmarkData'
              end

              all = load_all
              path = bookmark_data.path.to_s
              list = all[path] || []
              entry = bookmark_entry(bookmark_data)
              list << entry
              all[path] = list
              save_all(all)
              entry
            end

            def get(path)
              all = load_all
              list = all[path.to_s] || []
              list.map do |h|
                safe = h.is_a?(Hash) ? h.dup : {}
                safe['text'] = sanitize_text(safe['text'])
                Shoko::Core::Models::Bookmark.from_h(safe)
              end
            end

            def delete(path, bookmark)
              all = load_all
              key = path.to_s
              list = all[key] || []
              # Delete by matching serialized representation
              predicate = bookmark_predicate(bookmark)
              removed = list.find(&predicate)
              return nil unless removed

              list.reject!(&predicate)
              list.empty? ? all.delete(key) : all[key] = list
              save_all(all)
              removed
            end

            private

            def equivalent?(stored_entry, target)
              stored_entry['chapter'] == target['chapter'] &&
                stored_entry['line_offset'] == target['line_offset'] &&
                (stored_entry['text'].to_s == target['text'].to_s)
            end

            def bookmark_predicate(bookmark)
              case bookmark
              when Shoko::Core::Models::Bookmark
                target = bookmark.to_h
                ->(stored_entry) { equivalent?(stored_entry, target) }
              when Hash
                normalized = Shoko::Shared::HashNormalizer.symbolize_keys(bookmark) || {}
                chapter = normalized[:chapter_index] || normalized[:chapter]
                offset = normalized[:line_offset]
                lambda { |stored_entry|
                  stored_entry['chapter'] == chapter && stored_entry['line_offset'] == offset
                }
              else
                raise ArgumentError, 'bookmark must be a Bookmark or Hash'
              end
            end

            def bookmark_entry(bookmark_data)
              entry = {
                'chapter' => bookmark_data.chapter,
                'line_offset' => bookmark_data.line_offset,
                'text' => sanitize_text(bookmark_data.text),
                'timestamp' => Time.now.iso8601,
              }
              entry['anchor'] = bookmark_data.anchor if bookmark_data.anchor
              entry
            end

            def sanitize_text(text)
              Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
            end
          end
        end
      end
    end
  end
end
