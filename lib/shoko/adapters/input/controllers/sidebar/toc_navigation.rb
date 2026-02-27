# frozen_string_literal: true

require_relative '../../../../core/services/toc_tree_service'


module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          # TOC tree navigation and collapse-state mechanics.
          class TocNavigation
            def initialize(tree_service: Core::Services::TocTreeService.instance)
              @tree_service = tree_service
            end

            def entries_for(doc)
              @tree_service.entries_for(doc)
            end

            def collapsed_for(entries, raw = nil)
              entries = Array(entries)
              return [] if entries.empty?
              return @tree_service.default_collapsed(entries) if raw.nil?

              @tree_service.normalize_collapsed(entries, raw)
            end

            def visible_indices(entries, collapsed, filter_text: '', filter_active: false)
              @tree_service.visible_indices(
                entries,
                collapsed: collapsed,
                filter_text: filter_text,
                filter_active: filter_active
              )
            end

            def entry_has_children?(entries, index)
              @tree_service.entry_has_children?(entries, index)
            end

            def toggle_collapsed(collapsed, index)
              @tree_service.toggle_collapsed(collapsed, index)
            end

            def ensure_visible_selection(entries, collapsed, current, filter_text: '', filter_active: false)
              @tree_service.ensure_visible_selection(
                entries,
                collapsed,
                current,
                filter_text: filter_text,
                filter_active: filter_active
              )
            end

            def navigable_indices(entries, collapsed, filter_text: '', filter_active: false)
              @tree_service.navigable_indices(
                entries,
                collapsed,
                filter_text: filter_text,
                filter_active: filter_active
              )
            end

            def target_index(indices, current, delta)
              @tree_service.target_index(indices, current, delta)
            end

            def index_for_chapter(entries, chapter_index)
              @tree_service.index_for_chapter(entries, chapter_index)
            end
          end
        end
      end
    end
  end
end
