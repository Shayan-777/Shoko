# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Presentation::Ui::Components::EnhancedPopupMenu do
  let(:selection_range) do
    {
      start: { page_id: 0, geometry_key: nil, line_offset: 0, cell_index: 0, row: 0, column_origin: 0 },
      end: { page_id: 0, geometry_key: nil, line_offset: 0, cell_index: 0, row: 0, column_origin: 0 },
    }
  end

  let(:coordinate_service) do
    instance_double('CoordinateService',
                    normalize_selection_range: selection_range,
                    within_bounds?: true)
  end
  let(:popup_position_service) { instance_double('PopupPositionService', calculate_popup_position: { x: 1, y: 1 }) }

  let(:clipboard_service) { instance_double('ClipboardService', available?: clipboard_available) }

  describe 'default actions' do
    let(:clipboard_available) { false }

    it 'omits lookup when dictionary is disabled' do
      menu = described_class.new(selection_range, nil, coordinate_service, popup_position_service, clipboard_service, {},
                                 dictionary_enabled: false)
      labels = menu.instance_variable_get(:@available_actions).map { |action| action[:label] }

      expect(labels).to include('Create Annotation')
      expect(labels).not_to include('Look Up')
    end

    it 'includes lookup when dictionary is enabled' do
      menu = described_class.new(selection_range, nil, coordinate_service, popup_position_service, clipboard_service, {},
                                 dictionary_enabled: true)
      labels = menu.instance_variable_get(:@available_actions).map { |action| action[:label] }

      expect(labels).to include('Look Up')
    end

    it 'includes clipboard action when available' do
      allow(clipboard_service).to receive(:available?).and_return(true)
      menu = described_class.new(selection_range, nil, coordinate_service, popup_position_service, clipboard_service, {},
                                 dictionary_enabled: false)
      labels = menu.instance_variable_get(:@available_actions).map { |action| action[:label] }

      expect(labels).to include('Copy to Clipboard')
    end
  end
end
