# frozen_string_literal: true

require 'shoko/application/state/snapshot_factory'
require 'shoko/application/state/schema/menu_process'

module Shoko
  module Application
    module Ports
      module Outbound
        # Immutable state snapshots exposed by outbound state ports.
        module State
          # Port-contract snapshot for the persisted menu process slice.
          # Data contract for `Application::Ports::Outbound::MenuSessionStore`.
          MenuSessionSnapshot = Shoko::Application::State::SnapshotFactory.define_snapshot(
            fields: Shoko::Application::State::Schema::MenuProcess::FIELDS,
            defaults: Shoko::Application::State::Schema::MenuProcess::DEFAULTS,
            partition: :menu
          )

          MenuSessionSnapshot.class_eval do
            def search_active? = search_active == true
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
            def selected_library_index = library_selected
            def selected_annotation_record = selected_annotation
            def selected_annotation_book_path = selected_annotation_book
            def annotation_editor_text = annotation_edit_text
          end
        end
      end
    end
  end
end
