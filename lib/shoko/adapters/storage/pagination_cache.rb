# frozen_string_literal: true

require_relative 'epub_cache'
require_relative '../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Storage
      # Persists dynamic pagination layouts inside the on-disk cache for a book.
      module PaginationCache
        module_function

        SCHEMA_VERSION = 3

        def layout_key(width, height, view_mode, line_spacing, kitty_images: false, layout_variant: :base)
          suffix = kitty_images ? 'img1' : 'img0'
          variant = normalize_layout_variant(layout_variant)
          "#{width}x#{height}_#{view_mode}_#{line_spacing}_#{suffix}_#{variant}"
        end

        def parse_layout_key(key)
          return nil unless key

          dims, view_mode, line_spacing, image_mode, layout_variant = key.to_s.split('_', 5)
          width_str, height_str = dims.to_s.split('x', 2)
          return nil unless width_str && height_str && view_mode && line_spacing

          {
            width: width_str.to_i,
            height: height_str.to_i,
            view_mode: view_mode.to_sym,
            line_spacing: line_spacing.to_sym,
            kitty_images: image_mode.to_s == 'img1',
            layout_variant: normalize_layout_variant(layout_variant),
          }
        end

        def load_for_document(doc, key)
          cache = cache_for(doc)
          return nil unless cache

          data = cache.load_layout(key)
          extract_pages(data)
        end

        def save_for_document(doc, key, pages_compact)
          cache = cache_for(doc)
          return false unless cache

          payload = {
            'version' => SCHEMA_VERSION,
            'pages' => pages_compact,
          }
          cache.mutate_layouts! { |layouts| layouts[key] = payload }
        end

        def delete_for_document(doc, key)
          cache = cache_for(doc)
          return false unless cache

          cache.mutate_layouts! { |layouts| layouts.delete(key) }
        end

        def exists_for_document?(doc, key)
          cache = cache_for(doc)
          return false unless cache

          !!cache.load_layout(key)
        end

        def layout_keys_for_document(doc)
          cache = cache_for(doc)
          return [] unless cache

          cache.layout_keys
        end

        def extract_pages(data)
          payload = Shoko::Shared::HashNormalizer.deep_symbolize(data)
          return nil unless payload.is_a?(Hash)

          version = payload[:version]
          pages = payload[:pages]
          return nil unless pages.is_a?(Array)
          return nil if version && version.to_i != SCHEMA_VERSION

          pages.map { |entry| normalize_page_entry(entry) }
        end

        def cache_for(doc)
          path = resolve_cache_path(doc)
          return nil unless path && File.exist?(path)

          Shoko::Adapters::Storage::EpubCache.new(path)
        end
        private_class_method :cache_for

        def resolve_cache_path(doc)
          cache_path = doc&.cache_path
          return cache_path if cache_path && !cache_path.to_s.empty?

          canonical_path = doc&.canonical_path
          if canonical_path && File.exist?(canonical_path)
            cache = Shoko::Adapters::Storage::EpubCache.new(canonical_path)
            return cache.cache_path if File.exist?(cache.cache_path)
          end

          nil
        end
        private_class_method :resolve_cache_path

        def normalize_layout_variant(value)
          variant = value.to_s.strip
          variant = 'base' if variant.empty?
          variant.to_sym
        end
        private_class_method :normalize_layout_variant

        def normalize_page_entry(entry)
          normalized = Shoko::Shared::HashNormalizer.symbolize_keys(entry) || {}
          {
            chapter_index: normalized[:chapter_index],
            page_in_chapter: normalized[:page_in_chapter],
            total_pages_in_chapter: normalized[:total_pages_in_chapter],
            start_line: normalized[:start_line],
            end_line: normalized[:end_line],
          }
        end
        private_class_method :normalize_page_entry
      end
    end
  end
end
