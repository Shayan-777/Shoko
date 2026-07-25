# frozen_string_literal: true

require 'shoko/shared/errors'

module Shoko
  module Application
    module UseCases
      module Support
        # Loads every annotation into the menu snapshot before a screen that
        # displays them opens.
        #
        # Both the annotations screen and the navigation action that can jump
        # straight to it need the list warm, and both must degrade the same
        # way: a repository failure yields an empty list and a logged error
        # rather than an empty screen with no explanation.
        module AnnotationPreload
          private

          def preload_annotations
            annotations = @annotation_service ? @annotation_service.list_all : {}
            update_menu(annotations_all: annotations || {})
          rescue Shoko::Error => e
            @logger&.error('menu.preload_annotations.failed', error: e.class.name, message: e.message)
            update_menu(annotations_all: {})
          end
        end
      end
    end
  end
end
