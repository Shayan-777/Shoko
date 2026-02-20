# frozen_string_literal: true

require_relative '../base_component'
require_relative 'toc/index'

module Shoko
  module Adapters::Ui::Components
    module Sidebar
      # TOC tab renderer for sidebar
      class TocTabRenderer < BaseComponent
        include Adapters::Ui::Constants::Ui

        NullSurface = Struct.new(:_noop) do
          def write(*_args); end
        end
        private_constant :NullSurface

        def initialize(sidebar_state_reader:, document_provider:, text_metrics:)
          super()
          @sidebar_state_reader = sidebar_state_reader
          @document_provider = document_provider
          @text_metrics = text_metrics
          @wrap_cache = {}
          @cache_document_id = nil
          @entries_cache_key = nil
          @entries_cache = nil
        end

        def do_render(surface, bounds)
          doc = document
          refresh_wrap_cache(doc)
          entries_cache = entries_cache_for(doc, bounds)
          context = RenderContext.new(surface, bounds, doc, wrap_cache: @wrap_cache,
                                                           entries_cache: entries_cache,
                                                           sidebar_state_reader: sidebar_state_reader,
                                                           text_metrics: @text_metrics)
          @last_bounds_signature = bounds_signature(bounds)
          @last_scroll_metrics = context.scroll_metrics
          ComponentOrchestrator.new(context).render
        end

        def entry_at(bounds, col, row)
          return nil unless bounds

          local_row = row.to_i - bounds.y + 1
          local_col = col.to_i - bounds.x + 1
          return nil unless local_row.between?(1, bounds.height)
          return nil unless local_col.between?(1, bounds.width)

          doc = document
          refresh_wrap_cache(doc)
          entries_cache = entries_cache_for(doc, bounds)
          context = RenderContext.new(NullSurface.new, bounds, doc, wrap_cache: @wrap_cache,
                                                                    entries_cache: entries_cache,
                                                                    sidebar_state_reader: sidebar_state_reader,
                                                                    text_metrics: @text_metrics)
          context.entries_layout.item_at(local_row)
        end

        def scroll_metrics(bounds)
          return nil unless bounds

          signature = bounds_signature(bounds)
          return @last_scroll_metrics if @last_scroll_metrics && @last_bounds_signature == signature

          doc = document
          refresh_wrap_cache(doc)
          entries_cache = entries_cache_for(doc, bounds)
          context = RenderContext.new(NullSurface.new, bounds, doc, wrap_cache: @wrap_cache,
                                                                    entries_cache: entries_cache,
                                                                    sidebar_state_reader: sidebar_state_reader,
                                                                    text_metrics: @text_metrics)
          @last_bounds_signature = signature
          @last_scroll_metrics = context.scroll_metrics
        end

        private

        def document
          return nil unless @document_provider.respond_to?(:call)

          @document_provider.call
        rescue StandardError
          nil
        end

        def bounds_signature(bounds)
          [bounds.x, bounds.y, bounds.width, bounds.height]
        end

        def refresh_wrap_cache(doc)
          doc_id = doc&.object_id
          return if doc_id == @cache_document_id

          @cache_document_id = doc_id
          @wrap_cache.clear
        end

        def entries_cache_for(doc, bounds)
          key = entries_cache_key(doc)
          return @entries_cache if key == @entries_cache_key && @entries_cache

          context = RenderContext.new(NullSurface.new, bounds, doc, wrap_cache: @wrap_cache,
                                                                    sidebar_state_reader: sidebar_state_reader,
                                                                    text_metrics: @text_metrics)
          entries = EntriesCalculator.new(context).calculate
          @entries_cache = EntriesCache.new(full: entries.full, visible: entries.visible,
                                            visible_indices: entries.visible_indices)
          @entries_cache_key = key
          @entries_cache
        end

        def entries_cache_key(doc)
          filter_active = sidebar_state_reader&.sidebar_toc_filter_active?
          filter_text = sidebar_state_reader&.sidebar_toc_filter || ''
          collapsed = Array(sidebar_state_reader&.sidebar_toc_collapsed).map(&:to_i).sort
          [doc&.object_id, filter_active ? 1 : 0, filter_text.to_s, collapsed]
        end

        def sidebar_state_reader
          @sidebar_state_reader
        end
      end
    end
  end
end
