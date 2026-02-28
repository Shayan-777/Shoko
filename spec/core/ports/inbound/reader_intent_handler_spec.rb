# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Ports::Inbound::ReaderIntentHandler do
  let(:dummy_class) do
    Class.new do
      include Shoko::Core::Ports::Inbound::ReaderIntentHandler
    end
  end

  it 'defines explicit reader intent symbols' do
    expected = %i[
      annotation_editor_backspace
      annotation_editor_cancel
      annotation_editor_enter
      annotation_editor_insert_char_if_printable
      annotation_editor_move_down
      annotation_editor_move_left
      annotation_editor_move_right
      annotation_editor_move_up
      annotation_editor_save
      decrease_line_spacing
      dictionary_backspace
      dictionary_cancel
      dictionary_confirm
      dictionary_cycle_pair
      dictionary_cycle_result
      dictionary_insert_char_if_printable
      dictionary_scroll_down
      dictionary_scroll_up
      dictionary_swap_languages
      dictionary_toggle_fuzzy
      handle_popup_action_key
      handle_popup_cancel
      handle_popup_navigation
      help_exit_to_read
      in_book_search_backspace
      in_book_search_cancel
      in_book_search_confirm
      in_book_search_down
      in_book_search_insert_char_if_printable
      in_book_search_up
      increase_line_spacing
      invalidate_pagination_cache
      open_annotations
      open_annotations_tab
      open_bookmarks
      open_in_book_search
      open_toc
      quit_application
      quit_to_menu
      read_confirm_or_sidebar
      read_scroll_down_or_sidebar
      read_scroll_up_or_sidebar
      read_space_or_sidebar_toggle
      rebuild_pagination
      show_help
      toggle_page_numbering_mode
      toggle_view_mode
    ]

    expect(described_class::INTENT_SYMBOLS).to eq(expected)
  end

  it 'raises NotImplementedError for unimplemented methods by default' do
    instance = dummy_class.new

    expect { instance.handle_reader_intent(:show_help) }.to raise_error(NotImplementedError)
    expect { instance.command_logger }.to raise_error(NotImplementedError)
  end
end
