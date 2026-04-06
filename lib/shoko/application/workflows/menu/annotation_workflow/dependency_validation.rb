# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/menu_mode_switcher'
require_relative '../../../../core/ports/outbound/annotation_selection_reader'
require_relative '../../../../core/ports/outbound/annotation_view_refresher'
require_relative '../../../../core/ports/outbound/reader_runner'
require_relative '../../../../core/ports/outbound/menu_session_store'
require_relative '../../../../core/ports/outbound/menu_transient_store'
require_relative '../../../../core/ports/outbound/reader_session_store'

module Shoko
  module Application
    module Workflows
      module Menu
        # Shared dependency validation for AnnotationWorkflow. Keeping this
        # outside the workflow class prevents wiring concerns from dominating
        # the menu-side annotation behavior itself.
        module AnnotationWorkflowDependencyValidation
          REQUIRED_CONTRACTS = {
            mode_switcher: [
              Shoko::Core::Ports::Outbound::MenuModeSwitcher,
              'mode_switcher must implement Core::Ports::Outbound::MenuModeSwitcher',
            ],
            selected_annotation_reader: [
              Shoko::Core::Ports::Outbound::AnnotationSelectionReader,
              'selected_annotation_reader must implement Core::Ports::Outbound::AnnotationSelectionReader',
            ],
            annotations_view_refresher: [
              Shoko::Core::Ports::Outbound::AnnotationViewRefresher,
              'annotations_view_refresher must implement Core::Ports::Outbound::AnnotationViewRefresher',
            ],
            reader_runner: [
              Shoko::Core::Ports::Outbound::ReaderRunner,
              'reader_runner must implement Core::Ports::Outbound::ReaderRunner',
            ],
            menu_session_store: [
              Shoko::Core::Ports::Outbound::MenuSessionStore,
              'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore',
            ],
            reader_session_store: [
              Shoko::Core::Ports::Outbound::ReaderSessionStore,
              'reader_session_store must implement Core::Ports::Outbound::ReaderSessionStore',
            ],
          }.freeze

          REQUIRED_TRANSIENT_CONTRACTS = {
            menu_transient_store: [
              Shoko::Core::Ports::Outbound::MenuTransientStore,
              'menu_transient_store must implement Core::Ports::Outbound::MenuTransientStore',
            ],
          }.freeze

          private

          def validate_dependencies!(mode_switcher:, menu_session_store:, reader_session_store:, annotation_service:,
                                     selected_annotation_reader:, annotations_view_refresher:, reader_runner:,
                                     menu_transient_store:)
            validate_required_contracts(
              mode_switcher: mode_switcher,
              selected_annotation_reader: selected_annotation_reader,
              annotations_view_refresher: annotations_view_refresher,
              reader_runner: reader_runner,
              menu_session_store: menu_session_store,
              reader_session_store: reader_session_store
            )
            validate_required_transient_contracts(menu_transient_store:)
            raise ArgumentError, 'annotation_service is required' if annotation_service.nil?
          end

          def validate_contract!(value, contract, message)
            raise ArgumentError, message unless value.is_a?(contract)
          end

          def validate_required_contracts(**values)
            REQUIRED_CONTRACTS.each do |name, (contract, message)|
              validate_contract!(values.fetch(name), contract, message)
            end
          end

          def validate_required_transient_contracts(menu_transient_store:)
            contract, message = REQUIRED_TRANSIENT_CONTRACTS.fetch(:menu_transient_store)
            validate_contract!(menu_transient_store, contract, message)
          end
        end
      end
    end
  end
end
