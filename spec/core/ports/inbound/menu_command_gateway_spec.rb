# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Ports::Inbound::MenuCommandGateway do
  let(:dummy_class) do
    Class.new do
      include Shoko::Core::Ports::Inbound::MenuCommandGateway
    end
  end

  it 'defines explicit menu command contract methods' do
    expected = %i[
      annotation_editor_backspace
      annotation_editor_cancel
      annotation_editor_enter
      annotation_editor_insert_char
      annotation_editor_move_down
      annotation_editor_move_left
      annotation_editor_move_right
      annotation_editor_move_up
      annotation_editor_save
      annotations_down
      annotations_select
      annotations_up
      browse_down
      browse_up
      delete_selected_annotation
      dictionary_back
      dictionary_down
      dictionary_exit_search
      dictionary_refresh
      dictionary_search_backspace
      dictionary_search_delete
      dictionary_search_insert_char
      dictionary_select
      dictionary_start_search
      dictionary_submit_search
      dictionary_up
      download_confirm
      download_down
      download_exit_search
      download_next_page
      download_prev_page
      download_refresh
      download_search_backspace
      download_search_delete
      download_search_insert_char
      download_start_search
      download_submit_search
      download_up
      library_down
      library_select
      library_toggle_details
      library_up
      menu_back_to_root
      menu_nav_down
      menu_nav_up
      menu_quit
      menu_select
      open_selected_annotation
      open_selected_annotation_for_edit
      open_selected_book
      search_backspace
      search_delete
      search_insert_char
      settings_down
      settings_select
      settings_up
      switch_to_annotations_mode
      switch_to_browse
      switch_to_search
    ]

    expect(described_class::COMMAND_METHODS).to eq(expected)
  end

  it 'raises NotImplementedError for unimplemented methods by default' do
    instance = dummy_class.new

    expect { instance.command_logger }.to raise_error(NotImplementedError)
    described_class::COMMAND_METHODS.each do |method_name|
      expect { instance.public_send(method_name, nil) }.to raise_error(NotImplementedError)
    end
  end
end
