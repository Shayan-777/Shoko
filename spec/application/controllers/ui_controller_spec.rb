# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Controllers::UIController do
  let(:state) { instance_double('State', dispatch: nil, add_observer: nil, get: nil) }
  let(:dictionary_controller) { instance_double('DictionaryController', close_dictionary: nil) }

  def build_controller
    described_class.new(
      state: state,
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
      config_reader: instance_double('ConfigReader', theme: :dark)
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
