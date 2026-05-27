# frozen_string_literal: true

require_relative '../../../state/snapshot_support'
require_relative '../../../state/schema/menu_process'
require_relative '../../../state/schema/menu_transient'

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Composite menu snapshot covering the full `state[:menu]` partition:
          # the durable process slice + the transient workflow slice.
          #
          # Returned by the menu projection adapter for consumers that need
          # a single object exposing every menu field. New code should prefer
          # the focused snapshots (`MenuSessionSnapshot`,
          # `MenuTransientSnapshot`) — the composite is preserved for
          # workflow and use-case code that already reads/writes across slices.
          module MenuSnapshotInternal
            PROCESS_FIELDS = Shoko::Application::State::Schema::MenuProcess::FIELDS
            TRANSIENT_FIELDS = Shoko::Application::State::Schema::MenuTransient::FIELDS

            FIELDS = (PROCESS_FIELDS + TRANSIENT_FIELDS).freeze
            DEFAULTS = Shoko::Application::State::Schema::MenuProcess::DEFAULTS
                       .merge(Shoko::Application::State::Schema::MenuTransient::DEFAULTS)
                       .freeze
          end
          private_constant :MenuSnapshotInternal

          MenuSnapshot = Shoko::Application::State::SnapshotSupport.define_snapshot(
            fields: MenuSnapshotInternal::FIELDS,
            defaults: MenuSnapshotInternal::DEFAULTS,
            partition: :menu
          )

          MenuSnapshot.class_eval do
            def search_active? = search_active == true
            def loading_active? = loading_active == true
            def library_details_open? = library_details_open == true
            def wipe_cache_cached? = wipe_cache_cached.nil? || wipe_cache_cached == true
            def wipe_cache_downloads? = wipe_cache_downloads == true
            def wipe_cache_nuke? = wipe_cache_nuke == true
            def wipe_cache_annotations? = wipe_cache_annotations == true
            def wipe_cache_bookmarks? = wipe_cache_bookmarks == true
            def wipe_cache_config? = wipe_cache_config == true
            def wipe_cache_progress? = wipe_cache_progress == true
            def current_menu_mode = mode
            def selected_library_index = browse_selected
            def selected_annotation_record = selected_annotation
            def selected_annotation_book_path = selected_annotation_book
            def annotation_editor_text = annotation_edit_text
            def dictionary_entries = Array(dictionary_results)
          end
        end
      end
    end
  end
end
