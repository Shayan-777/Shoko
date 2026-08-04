# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Builds dependency records without silently discarding misspelled or
          # stale wiring keys. Composite bundles explicitly project a validated
          # union of keywords into their child records.
          module DependencyBuilder
            def build(**kwargs)
              reject_unknown_dependencies!(kwargs.keys)
              new(**kwargs)
            end

            def build_from(validated_dependencies)
              new(**validated_dependencies.slice(*members))
            end

            def reject_unknown_dependencies!(keys, allowed: members, label: name.split('::').last)
              unknown = keys - allowed
              return if unknown.empty?

              raise ArgumentError,
                    "Unknown #{label} dependencies: #{unknown.map(&:inspect).join(', ')}"
            end
          end
        end
      end
    end
  end
end
