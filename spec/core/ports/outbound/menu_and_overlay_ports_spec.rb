# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Application menu and overlay port contracts' do
  def build_implementation(port_module)
    Class.new do
      include port_module
    end.new
  end

  def expect_contract_methods_to_raise(implementation, methods)
    methods.each do |method_name, args|
      expect { implementation.public_send(method_name, *args) }.to raise_error(NotImplementedError)
    end
  end

  it 'defines MenuNavigationReader contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuNavigationReader)
    methods = %i[
      selected
      mode
      browse_selected
      settings_selected
      download_selected
      dictionary_selected
      wipe_cache_cached?
      wipe_cache_downloads?
      wipe_cache_nuke?
      wipe_cache_annotations?
      wipe_cache_bookmarks?
      wipe_cache_config?
      wipe_cache_progress?
    ].map { |name| [name, []] }

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuQueryReader contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuQueryReader)
    methods = %i[
      search_query
      search_cursor
      search_active?
      download_query
      download_cursor
      dictionary_query
      dictionary_cursor
    ].map { |name| [name, []] }

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuDataReader contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuDataReader)
    methods = %i[
      download_status
      download_progress
      download_next
      download_prev
      download_results
      download_message
      download_count
      dictionary_status
      dictionary_progress
      dictionary_results
      dictionary_message
    ].map { |name| [name, []] }

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines MenuStateWriter contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::MenuStateWriter)
    methods = [
      [:update_menu, [{}]],
      [:update_selected, [0]],
      [:update_browse_selected, [0]],
      [:update_mode, [:menu]],
      [:update_search, []],
      [:update_settings_selected, [0]],
      [:update_download, []],
      [:update_dictionary, []],
      [:update_annotation_edit, []],
      [:update_selected_annotation, []],
      [:update_annotations_all, [{}]],
      [:update_loading, []]
    ]

    expect_contract_methods_to_raise(implementation, methods)
  end

  it 'defines ReaderOverlayStateReader contract methods' do
    implementation = build_implementation(Shoko::Core::Ports::Outbound::ReaderOverlayStateReader)
    methods = %i[
      mode
      selection
      popup_menu
      in_book_search_popup
      annotations_overlay
      annotation_editor_overlay
      dictionary_popup
      dictionary_panel
      running?
      sidebar_visible?
      sidebar_active_tab
    ].map { |name| [name, []] }

    expect_contract_methods_to_raise(implementation, methods)
  end
end
