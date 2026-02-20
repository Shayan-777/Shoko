# frozen_string_literal: true

require_relative 'state_controller/progress_actions'
require_relative 'state_controller/bookmark_actions'
require_relative 'state_controller/annotation_actions'

module Shoko
  module Application
    module Controllers
      # Handles all state management: persistence, bookmarks, progress.
      class StateController
        include StateControllerProgressActions
        include StateControllerBookmarkActions
        include StateControllerAnnotationActions

        def initialize(reader_state:, config_reader:, ui_state:, sidebar_state:,
                       state_writer:, rendered_content_reader:, doc:, path:, terminal_service:,
                       progress_repository: nil, bookmark_repository: nil,
                       annotation_service: nil, logger: nil, navigation_service: nil,
                       page_calculator: nil, layout_service: nil, bookmark_service: nil,
                       notification_service: nil, coordinate_service: nil, process_control: nil)
          @reader_state = reader_state
          @config_reader = config_reader
          @ui_state = ui_state
          @sidebar_state = sidebar_state
          @state_writer = state_writer
          @rendered_content_reader = rendered_content_reader
          @doc = doc
          @path = path
          @terminal_service = terminal_service
          @progress_repository = progress_repository
          @bookmark_repository = bookmark_repository
          @annotation_service = annotation_service
          @logger = logger
          @navigation_service = navigation_service
          @page_calculator = page_calculator
          @layout_service = layout_service
          @bookmark_service = bookmark_service
          @notification_service = notification_service
          @coordinate_service = coordinate_service
          @process_control = process_control
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
