# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'

module Shoko
  module Application
    module Services
      module Pagination
        module Internal
          # Tracks active/cached dynamic layouts and resolves layout context for page hydration.
          class DynamicLayoutCache
            def initialize(cache_limit:)
              @cache_limit = [cache_limit.to_i, 1].max
              reset!
            end

            attr_reader :pages_data

            def reset!
              @pages_data = []
              @layouts = {}
              @layout_order = []
              @active_layout_key = nil
              @last_layout_width = nil
              @last_layout_height = nil
            end

            def total_pages
              @pages_data.size
            end

            def remember_layout(width:, height:)
              @last_layout_width = width.to_i
              @last_layout_height = height.to_i
            end

            def raw_page(page_index)
              return nil if @pages_data.empty?

              index = page_index.to_i
              return @pages_data.first if index.negative?

              index = @pages_data.length - 1 if index >= @pages_data.length
              @pages_data[index]
            end

            def replace_page(page_index, page)
              return page unless page

              index = page_index.to_i
              return page if index.negative? || index >= @pages_data.length

              @pages_data[index] = normalize_page(page)
            end

            def cached?(key)
              key && @layouts.key?(key)
            end

            def cached_pages(key)
              return nil unless key

              @layouts[key]
            end

            def cache_pages(key:, pages:)
              return unless key && pages.is_a?(Array)

              @layouts[key] = normalize_pages(pages)
              @layout_order.delete(key)
              @layout_order << key
              evict_old_layouts!
            end

            def activate(key:, pages:, width:, height:)
              normalized_pages = normalize_pages(pages)
              cache_pages(key: key, pages: normalized_pages)
              @active_layout_key = key
              @pages_data = normalized_pages
              remember_layout(width: width, height: height)
              normalized_pages
            end

            def load_pages(pages:, key: nil, width: nil, height: nil)
              @pages_data = normalize_pages(pages)
              return unless width && height

              cache_pages(key: key, pages: @pages_data) if key
              @active_layout_key = key if key
              remember_layout(width: width, height: height)
            end

            def layout_context(width: nil, height: nil)
              context_from_explicit_layout(width: width, height: height) ||
                context_from_last_layout ||
                context_from_active_layout_key ||
                default_layout_context
            end

            private

            def evict_old_layouts!
              while @layout_order.length > @cache_limit
                oldest = @layout_order.shift
                next if oldest == @active_layout_key

                @layouts.delete(oldest)
              end
            end

            def context_from_explicit_layout(width:, height:)
              return nil unless width && height

              {
                width: width.to_i,
                height: height.to_i,
              }
            end

            def context_from_last_layout
              return nil unless @last_layout_width.to_i.positive? && @last_layout_height.to_i.positive?

              {
                width: @last_layout_width,
                height: @last_layout_height,
              }
            end

            def context_from_active_layout_key
              key = @active_layout_key.to_s
              return nil if key.empty?

              parts = key.split(':')
              width = parts[0].to_i
              height = parts[1].to_i
              return nil unless width.positive? && height.positive?

              {
                width: width,
                height: height,
              }
            end

            def default_layout_context
              { width: 80, height: 24 }
            end

            def normalize_pages(pages)
              Array(pages).map { |page| normalize_page(page) }
            end

            def normalize_page(page)
              return page unless page.is_a?(Hash)

              Shoko::Shared::HashNormalizer.deep_symbolize(page) || {}
            end
          end
        end
      end
    end
  end
end
