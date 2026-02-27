# frozen_string_literal: true

require_relative 'state_controller/progress_actions'
require_relative 'state_controller/bookmark_actions'
require_relative 'state_controller/annotation_actions'

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
            :state_writer,
            :rendered_content_reader,
            :doc,
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
              state_writer
            ].freeze

            def validate!
              missing = REQUIRED_FIELDS.select { |field| public_send(field).nil? }
              return self if missing.empty?

              raise ArgumentError, "Missing required state controller dependencies: #{missing.join(', ')}"
            end
          end

          include StateControllerProgressActions
          include StateControllerBookmarkActions
          include StateControllerAnnotationActions

          def initialize(deps:)
            deps.validate!

            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @ui_state = deps.ui_state
            @sidebar_state = deps.sidebar_state
            @state_writer = deps.state_writer
            @rendered_content_reader = deps.rendered_content_reader
            @doc = deps.doc
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

          def set_message(text, duration = 2)
            if @notification_service
              @notification_service.set_message(text, duration)
            else
              @state_writer.update_reader(message: text)
            end
          rescue StandardError
            @state_writer.update_reader(message: text)
          end
        end
      end
    end
  end
end
