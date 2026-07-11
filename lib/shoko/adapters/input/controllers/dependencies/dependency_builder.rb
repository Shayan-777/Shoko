# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Builds dependency records from a wider keyword hash at composition boundaries.
          module DependencyBuilder
            def build(**kwargs)
              new(**kwargs.slice(*members))
            end
          end
        end
      end
    end
  end
end
