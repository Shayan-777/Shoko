# frozen_string_literal: true

require_relative '../../../state/snapshot_factory'
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
          # This is the deliberate cross-slice read model — use it when a
          # consumer needs a unified view of the whole menu partition (e.g.
          # `MenuSessionAccess#current_menu`, which merges the session + transient
          # stores and splits writes back across them, and the menu projection
          # adapter). Use the focused snapshots (`MenuSessionSnapshot`,
          # `MenuTransientSnapshot`) when a consumer only touches a single slice.
          # The two levels coexist by design; this is not a legacy shim.
          module MenuSnapshotInternal
            PROCESS_FIELDS = Shoko::Application::State::Schema::MenuProcess::FIELDS
            TRANSIENT_FIELDS = Shoko::Application::State::Schema::MenuTransient::FIELDS

            FIELDS = (PROCESS_FIELDS + TRANSIENT_FIELDS).freeze
            DEFAULTS = Shoko::Application::State::Schema::MenuProcess::DEFAULTS
                       .merge(Shoko::Application::State::Schema::MenuTransient::DEFAULTS)
                       .freeze
          end
          private_constant :MenuSnapshotInternal

          MenuSnapshot = Shoko::Application::State::SnapshotFactory.define_snapshot(
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
            def wipe_cache_dictionary? = wipe_cache_dictionary == true
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
