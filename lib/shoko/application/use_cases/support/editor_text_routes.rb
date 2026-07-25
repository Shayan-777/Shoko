# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Support
        # The annotation editor's text-editing intent route.
        #
        # The menu-side and reader-side editors are separate action groups
        # driving the same editor operator, so the binding from
        # `edit_annotation_text` to the operator is declared once.
        module EditorTextRoutes
          private

          def editor_text_routes
            {
              edit_annotation_text: route(payload: :edit_op, result: :handled) do |op|
                operator.apply(op)
              end,
            }
          end
        end
      end
    end
  end
end
