# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Ports::Inbound::ReaderIntentHandler do
  let(:dummy_class) do
    Class.new do
      include Shoko::Application::Ports::Inbound::ReaderIntentHandler
    end
  end

  it 'defines explicit reader intent symbols' do
    expected = %i[
      next_page
      prev_page
      scroll_down
      scroll_up
      next_chapter
      prev_chapter
      go_to_start
      go_to_end
      add_bookmark
      open_toc_sidebar
      open_bookmarks_sidebar
      open_annotations_sidebar
      open_annotations_overlay
      open_help_overlay
      close_help_overlay
      toggle_view_mode
      toggle_page_numbering_mode
      increase_line_spacing
      decrease_line_spacing
      toggle_sidebar
      sidebar_move_up
      sidebar_move_down
      sidebar_activate
      open_dictionary
      close_dictionary
      edit_reader_dictionary_query
      dictionary_confirm
      dictionary_move_up
      dictionary_move_down
      dictionary_cycle_result
      dictionary_cycle_pair
      dictionary_swap_languages
      dictionary_toggle_fuzzy
      open_in_book_search
      close_in_book_search
      edit_in_book_search
      search_confirm
      search_move_up
      search_move_down
      open_toc
      close_toc
      edit_toc_filter
      toc_confirm
      toc_move_up
      toc_move_down
      open_translator
      close_translator
      edit_translator
      translator_confirm
      translator_cursor_move
      translator_cycle_picker
      translator_swap_languages
      edit_annotation_text
      move_annotation_cursor
      annotation_editor_save
      annotation_editor_cancel
      annotation_editor_spellcheck
      annotation_editor_confirm
      popup_move_up
      popup_move_down
      popup_confirm
      popup_cancel
      rebuild_pagination
      clear_pagination_cache
      quit_to_menu
      quit_application
    ]

    expect(described_class::INTENT_SYMBOLS).to eq(expected)
  end

  it 'raises NotImplementedError for unimplemented methods by default' do
    instance = dummy_class.new

    expect { instance.handle_reader_intent(:open_help_overlay) }.to raise_error(NotImplementedError)
  end
end
