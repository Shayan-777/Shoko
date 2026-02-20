# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::UIController do
  let(:dictionary_controller) { instance_double('DictionaryController', close_dictionary: nil) }
  let(:reader_state) do
    instance_double('ReaderStateReader',
                    current_chapter: 0, bookmarks: [], annotations: [],
                    selection: nil, sidebar_visible?: false,
                    sidebar_active_tab: :toc, sidebar_annotations_selected: 0,
                    mode: :read, running?: true, message: nil, popup_menu: nil,
                    annotations_overlay: nil, annotation_editor_overlay: nil,
                    dictionary_popup: nil, dictionary_panel: nil)
  end
  let(:config_reader) do
    instance_double('ConfigReader', theme: :dark, view_mode: :single,
                    line_spacing: :normal, page_numbering_mode: :dynamic,
                    show_page_numbers: true)
  end
  let(:state_writer) do
    instance_double('StateWriter', update_reader: nil, update_config: nil,
                    update_sidebar: nil, update_selections: nil,
                    update_page: nil, clear_selection: nil,
                    toggle_view_mode: nil)
  end
  let(:sidebar_state) do
    instance_double('SidebarStateReader',
                    sidebar_visible?: false, sidebar_active_tab: :toc,
                    sidebar_toc_selected: 0, sidebar_toc_collapsed: nil,
                    sidebar_bookmarks_selected: 0, sidebar_annotations_selected: 0,
                    sidebar_prev_view_mode: nil)
  end
  let(:ui_state) do
    instance_double('UIStateReader', terminal_width: 80, terminal_height: 24)
  end

  def build_controller
    described_class.new(
      reader_state: reader_state,
      config_reader: config_reader,
      state_writer: state_writer,
      sidebar_state: sidebar_state,
      ui_state: ui_state,
      notification_service: nil,
      selection_service: nil,
      rendered_content_reader: nil,
      clipboard_service: nil,
      ui_component_factory: nil,
      input_controller: nil,
      reader_controller: nil,
      state_controller: nil,
      annotation_service: nil,
      dictionary_service: nil,
      terminal_service: nil,
      layout_metrics: nil,
      layout_service: nil,
      document: nil,
      navigation_service: nil,
      bookmark_service: nil,
      render_registry: nil,
      settings_service: nil,
      logger: nil,
      dictionary_availability: nil,
      formatting_service: nil,
      clock: instance_double('Clock', monotonic_now: 1.0)
    ).tap do |controller|
      controller.instance_variable_set(:@dictionary_controller, dictionary_controller)
    end
  end

  it 'allows close_dictionary to be called with a key argument' do
    controller = build_controller
    expect(dictionary_controller).to receive(:close_dictionary)

    controller.close_dictionary('q')
  end
end
