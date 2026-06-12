# frozen_string_literal: true

require 'shoko/application/ports/outbound/annotation_editor_launcher'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Bridges annotation editor launch requests through the UI session adapter.
        class AnnotationEditorLauncherAdapter
          include Shoko::Application::Ports::Outbound::AnnotationEditorLauncher

          def initialize(annotation_overlay_ui_session:)
            @annotation_overlay_ui_session = annotation_overlay_ui_session
          end

          def open_editor(text:, range:, chapter_index:, annotation:)
            @annotation_overlay_ui_session.open_editor(
              text: text,
              range: range,
              chapter_index: chapter_index,
              annotation: annotation
            )
          end
        end
      end
    end
  end
end
