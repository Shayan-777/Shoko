# frozen_string_literal: true

require_relative 'dependencies/state_controller_dependencies'
require_relative 'state_controller/progress_actions'
require_relative 'state_controller/bookmark_actions'
require_relative 'state_controller/annotation_actions'
require_relative 'support/message_notifier'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles all state management: persistence, bookmarks, progress.
        class StateController
          Dependencies = Shoko::Adapters::Input::Controllers::Dependencies::StateControllerDependencies::Bundle

          include StateControllerProgressActions
          include StateControllerBookmarkActions
          include StateControllerAnnotationActions
          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

          def initialize(deps:)
            dependencies = deps.validate!
            assign_session_dependencies(dependencies.session)
            assign_document_dependencies(dependencies.document)
            assign_service_dependencies(dependencies.services)
          end

          private

          def assign_session_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @ui_state = deps.ui_state
            @sidebar_state = deps.sidebar_state
            @reader_session_mutator = deps.reader_session_mutator
            @rendered_content_reader = deps.rendered_content_reader
          end

          def assign_document_dependencies(deps)
            @doc = deps.doc
            @document_reader = deps.document_reader
            @path = deps.path
            @terminal_service = deps.terminal_service
            @page_calculator = deps.page_calculator
            @layout_service = deps.layout_service
            @process_control = deps.process_control
          end

          def assign_service_dependencies(deps)
            @progress_repository = deps.progress_repository
            @bookmark_repository = deps.bookmark_repository
            @annotation_service = deps.annotation_service
            @logger = deps.logger
            @navigation_service = deps.navigation_service
            @bookmark_service = deps.bookmark_service
            @notification_service = deps.notification_service
            @coordinate_service = deps.coordinate_service
          end
        end
      end
    end
  end
end
