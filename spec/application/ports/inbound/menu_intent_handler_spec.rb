# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Ports::Inbound::MenuIntentHandler do
  let(:dummy_class) do
    Class.new do
      include Shoko::Application::Ports::Inbound::MenuIntentHandler
    end
  end

  it 'defines explicit menu intent symbols' do
    expected = %i[
      move_menu_selection_up
      move_menu_selection_down
      activate_menu_selection
      switch_to_menu_mode
      switch_to_browse_mode
      switch_to_search_mode
      open_rss_reader_mode
      close_rss_reader_mode
      move_browse_selection_up
      move_browse_selection_down
      open_selected_book
      edit_browse_search
      move_library_selection_up
      move_library_selection_down
      activate_library_selection
      toggle_library_details
      move_settings_selection_up
      move_settings_selection_down
      activate_settings_selection
      open_dictionary_mode
      close_dictionary_mode
      refresh_dictionary_results
      move_dictionary_selection_up
      move_dictionary_selection_down
      activate_dictionary_selection
      edit_menu_dictionary_query
      submit_dictionary_query
      open_translator_packs_mode
      close_translator_packs_mode
      refresh_translator_packs
      move_translator_packs_selection_up
      move_translator_packs_selection_down
      activate_translator_packs_selection
      edit_translator_packs_query
      submit_translator_packs_query
      open_download_mode
      close_download_mode
      open_download_source_mode
      close_download_source_mode
      refresh_download_results
      move_download_selection_up
      move_download_selection_down
      move_download_source_selection_up
      move_download_source_selection_down
      activate_download_selection
      activate_download_source_selection
      edit_download_query
      submit_download_query
      download_next_page
      download_prev_page
      close_translator_mode
      close_translator_dropdown
      translator_cycle_focus
      translator_activate_focus
      translator_submit
      translator_swap_languages
      edit_translator_input
      edit_translator_language_query
      move_translator_cursor
      move_translator_language_selection_up
      move_translator_language_selection_down
      activate_translator_language_selection
      rss_reader_focus_left
      rss_reader_focus_right
      rss_reader_cycle_focus
      rss_reader_cycle_focus_back
      rss_reader_activate_selection
      rss_reader_move_up
      rss_reader_move_down
      rss_reader_go_top
      rss_reader_go_bottom
      rss_reader_page_down
      rss_reader_page_up
      rss_reader_sync
      rss_reader_toggle_zen
      rss_reader_show_all
      rss_reader_show_unread
      rss_reader_show_starred
      rss_reader_mark_read
      rss_reader_mark_unread
      rss_reader_mark_starred
      rss_reader_unstar
      rss_reader_open_add_feed
      edit_rss_feed_input
      rss_reader_submit_add_feed
      rss_reader_open_filter
      edit_rss_filter
      rss_reader_submit_filter
      rss_reader_remove_feed
      rss_reader_copy_selection
      rss_reader_lookup_selection
      rss_reader_translate_selection
      rss_reader_annotate_selection
      rss_reader_clear_selection
      rss_reader_open_find
      edit_rss_find
      rss_reader_submit_find
      rss_reader_next_match
      rss_reader_prev_match
      rss_reader_close_find
      open_annotations_mode
      move_annotation_selection_up
      move_annotation_selection_down
      activate_annotation_selection
      open_selected_annotation
      edit_selected_annotation
      delete_selected_annotation
      edit_annotation_text
      move_annotation_cursor
      annotation_editor_save
      annotation_editor_cancel
      quit_application
    ]

    expect(described_class::INTENT_SYMBOLS).to eq(expected)
  end

  it 'raises NotImplementedError for unimplemented methods by default' do
    instance = dummy_class.new

    expect { instance.handle_menu_intent(:activate_menu_selection) }.to raise_error(NotImplementedError)
  end
end
