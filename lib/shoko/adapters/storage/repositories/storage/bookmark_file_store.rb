# frozen_string_literal: true

require 'time'
require_relative '../../../../shared/text_sanitizer'
require_relative '../../../../core/models/bookmark'
require_relative '../../../../core/models/bookmark_data'
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

            def add(bookmark_data)
              unless bookmark_data.is_a?(Shoko::Core::Models::BookmarkData)
                raise ArgumentError, 'bookmark_data must be BookmarkData'
              end

              all = load_all
              path = bookmark_data.path.to_s
              list = all[path] || []
              entry = {
                'chapter' => bookmark_data.chapter,
                'line_offset' => bookmark_data.line_offset,
                'text' => sanitize_text(bookmark_data.text),
                'timestamp' => Time.now.iso8601,
              }
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
            rescue Shoko::Error
              []
            end

            def delete(path, bookmark)
              all = load_all
              key = path.to_s
              list = all[key] || []
              # Delete by matching serialized representation
              predicate = bookmark_predicate(bookmark)
              list.reject!(&predicate)
              list.empty? ? all.delete(key) : all[key] = list
              save_all(all)
              true
            rescue Shoko::Error
              raise
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
                chapter = bookmark[:chapter_index] || bookmark['chapter_index'] || bookmark[:chapter] || bookmark['chapter']
                offset = bookmark[:line_offset] || bookmark['line_offset']
                lambda { |stored_entry|
                  stored_entry['chapter'] == chapter && stored_entry['line_offset'] == offset
                }
              else
                raise ArgumentError, 'bookmark must be a Bookmark or Hash'
              end
            end

            def sanitize_text(text)
              Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: false,
                                                               preserve_tabs: false)
            end
          end
        end
      end
    end
  end
end
