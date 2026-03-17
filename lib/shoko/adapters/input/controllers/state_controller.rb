# frozen_string_literal: true

require_relative 'state_controller/progress_actions'
require_relative 'state_controller/bookmark_actions'
require_relative 'state_controller/annotation_actions'
require_relative 'support/message_notifier'
require_relative '../../../core/ports/outbound/progress_repository'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles all state management: persistence, bookmarks, progress.
        class StateController
          Dependencies = Data.define(
            :reader_state,
            :config_reader,
            :ui_state,
            :sidebar_state,
            :reader_session_mutator,
            :rendered_content_reader,
            :doc,
            :document_reader,
            :path,
            :terminal_service,
            :progress_repository,
            :bookmark_repository,
            :annotation_service,
            :logger,
            :navigation_service,
            :page_calculator,
            :layout_service,
            :bookmark_service,
            :notification_service,
            :coordinate_service,
            :process_control
          ) do
            REQUIRED_FIELDS = %i[
              reader_state
              config_reader
              ui_state
              sidebar_state
              reader_session_mutator
              progress_repository
              notification_service
            ].freeze

            def validate!
              values = to_h
              missing = REQUIRED_FIELDS.select { |field| values[field].nil? }
              unless missing.empty?
                raise ArgumentError, "Missing required state controller dependencies: #{missing.join(', ')}"
              end

              unless progress_repository.is_a?(Shoko::Core::Ports::Outbound::ProgressRepository)
                raise ArgumentError, 'progress_repository must implement Core::Ports::Outbound::ProgressRepository'
              end

              self
            end
          end

          include StateControllerProgressActions
          include StateControllerBookmarkActions
          include StateControllerAnnotationActions
          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

          def initialize(deps:)
            deps.validate!

            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @ui_state = deps.ui_state
            @sidebar_state = deps.sidebar_state
            @reader_session_mutator = deps.reader_session_mutator
            @rendered_content_reader = deps.rendered_content_reader
            @doc = deps.doc
            @document_reader = deps.document_reader
            @path = deps.path
            @terminal_service = deps.terminal_service
            @progress_repository = deps.progress_repository
            @bookmark_repository = deps.bookmark_repository
            @annotation_service = deps.annotation_service
            @logger = deps.logger
            @navigation_service = deps.navigation_service
            @page_calculator = deps.page_calculator
            @layout_service = deps.layout_service
            @bookmark_service = deps.bookmark_service
            @notification_service = deps.notification_service
            @coordinate_service = deps.coordinate_service
            @process_control = deps.process_control
          end

          private
        end
      end
    end
  end
end
