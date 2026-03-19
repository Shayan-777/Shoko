# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          class SelectionCoordinator
            # Handles bookmark and annotation list selection within the sidebar surface.
            module ListFlow
              private

              def select_bookmark
                bookmark = select_list_item(@reader_state.bookmarks, @sidebar_state.sidebar_bookmarks_selected)
                return unless bookmark

                if @bookmark_service
                  @bookmark_service.jump_to_bookmark(bookmark)
                  @state_controller&.save_progress
                end
                @close_sidebar.call(:bookmarks)
              end

              def select_annotation
                annotation = select_list_item(@reader_state.annotations, @sidebar_state.sidebar_annotations_selected)
                return unless annotation

                @state_controller&.jump_to_annotation(annotation)
                @close_sidebar.call(:annotations)
              end

              def select_list_item(items, raw_index)
                items = Array(items)
                selected = (raw_index || 0).to_i.clamp(0, [items.length - 1, 0].max)
                items[selected]
              end

              def move_list(delta, list_key, state_key)
                items = sidebar_list_items(list_key)
                current = sidebar_list_selection(state_key)
                new_val = (current + delta).clamp(0, [items.length - 1, 0].max)

                @reader_session_mutator.update_sidebar(state_key.to_s.sub('sidebar_', '').to_sym => new_val)
              end

              def sidebar_list_items(list_key)
                case list_key
                when :annotations then @reader_state.annotations || []
                when :bookmarks then @reader_state.bookmarks || []
                else []
                end
              end

              def sidebar_list_selection(state_key)
                case state_key
                when :sidebar_annotations_selected then @sidebar_state.sidebar_annotations_selected || 0
                when :sidebar_bookmarks_selected then @sidebar_state.sidebar_bookmarks_selected || 0
                else 0
                end
              end
            end
          end
        end
      end
    end
  end
end
