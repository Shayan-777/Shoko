# frozen_string_literal: true

require_relative 'dependency_validation'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Reader-facing application services injected into the controller graph.
          ReaderControllerServiceDependencies = Data.define(
            :navigation_service,
            :bookmark_service,
            :popup_position_service,
            :rendered_content_reader,
            :annotation_service,
            :render_registry,
            :coordinate_service
          ) do
            include DependencyValidation

            def self.required_fields
              %i[rendered_content_reader coordinate_service]
            end
          end
        end
      end
    end
  end
end
