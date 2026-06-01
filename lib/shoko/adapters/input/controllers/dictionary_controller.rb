# frozen_string_literal: true

require_relative 'dependencies/dictionary_controller_dependencies'
require_relative 'dictionary/index'
require_relative 'dictionary/session_actions'
require_relative 'support/session_outcome_helpers'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles dictionary lookups and dictionary UI lifecycle.
        class DictionaryController
          include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeHelpers

          Dependencies = Shoko::Adapters::Input::Controllers::Dependencies::DictionaryControllerDependencies::Bundle

          include Dictionary::ControllerSupport
          include Dictionary::DisplayModeSupport
          include Dictionary::LanguagePairSupport
          include Dictionary::SessionActions
          include Dictionary::SetupFlowSupport

          def initialize(deps:)
            dependencies = deps.validate!
            assign_state_dependencies(dependencies.state)
            assign_service_dependencies(dependencies.services)
            assign_ui_dependencies(dependencies.ui)
            assign_controller_dependencies(dependencies.controllers)
            @manual_source_lang_by_book = {}
            @setup_session = nil
          end

          def handle_lookup_action(action_data)
            lookup_word = lookup_word_for_action(action_data)
            return reject_lookup('No text selected for lookup') if lookup_word.nil? || lookup_word.empty?
            return reject_lookup('Dictionary service not available') unless @dictionary_service

            @reader_session_mutator.update_reader(popup_menu: nil)
            begin_lookup_with_setup(query: lookup_word)
          end

          def show_dictionary_panel(result, announce: true)
            outcome = @dictionary_ui_session&.show_panel(result)
            return unless session_ok?(outcome)

            @setup_session = nil
            @reader_controller&.rebuild_root_layout
            activate_dictionary_mode
            set_message("Looking up '#{result.query}'", 2) if announce
          end

          def show_dictionary_popup(result, announce: true)
            outcome = @dictionary_ui_session&.show_popup(result)
            return unless session_ok?(outcome)

            @setup_session = nil
            @reader_controller&.rebuild_root_layout
            activate_dictionary_mode
            set_message("Looking up '#{result.query}'", 2) if announce
          end

          def close_dictionary
            @dictionary_ui_session&.close
            @setup_session = nil
            @reader_session_mutator.clear_selection
            @reader_controller&.rebuild_root_layout
            deactivate_dictionary_mode
          end

          private

          def assign_state_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @sidebar_state = deps.sidebar_state
            @reader_session_mutator = deps.reader_session_mutator
            @document = deps.document
            @rendered_content_reader = deps.rendered_content_reader
          end

          def assign_service_dependencies(deps)
            @dictionary_service = deps.dictionary_service
            @dictionary_catalog_service = deps.dictionary_catalog_service
            @dictionary_availability = deps.dictionary_availability
            @dictionary_storage = deps.dictionary_storage
            @selection_service = deps.selection_service
            @notification_service = deps.notification_service
            @settings_service = deps.settings_service
          end

          def assign_ui_dependencies(deps)
            @layout_metrics = deps.layout_metrics
            @terminal_service = deps.terminal_service
            @ui_component_factory_inst = deps.ui_component_factory
            @dictionary_ui_session = deps.dictionary_ui_session
          end

          def assign_controller_dependencies(deps)
            @logger = deps.logger
            @input_controller = deps.input_controller
            @layout_service = deps.layout_service
            @reader_controller = deps.reader_controller
            @ui_controller = deps.ui_controller
            @clock = deps.clock
          end

          def lookup_word_for_action(action_data)
            selected_text = extract_selected_text_from_selection(selection_range_for(action_data))
            return nil if selected_text.nil? || selected_text.strip.empty?

            extract_lookup_word(selected_text)
          end

          def selection_range_for(action_data)
            return @reader_state.selection unless action_data.is_a?(Hash)

            action_data.dig(:data, :selection_range)
          end

          def reject_lookup(message)
            set_message(message)
            cleanup_popup_state
            nil
          end
        end
      end
    end
  end
end
