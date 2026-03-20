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

          # Validates dependency records against explicit required field lists.
          module Validation
            def validate!
              missing = Array(self.class.required_fields).select { |field| public_send(field).nil? }
              return self if missing.empty?

              raise ArgumentError, "Missing required #{self.class.name.split('::').last}: #{missing.join(', ')}"
            end
          end
        end
      end
    end
  end
end
