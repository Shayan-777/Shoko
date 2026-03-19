# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Duplicates only the requested state subtree for snapshot materialization.
        module BranchSnapshotSupport
          IMMUTABLE_LEAF_TYPES = [NilClass, TrueClass, FalseClass, Numeric, Symbol].freeze

          private

          def duplicate_fields(source, fields)
            Array(fields).to_h do |field|
              [field, duplicate_branch(source[field])]
            end
          end

          def duplicate_branch(value)
            case value
            when Hash
              value.each_with_object({}) do |(key, inner_value), acc|
                acc[key] = duplicate_branch(inner_value)
              end
            when Array
              value.map { |item| duplicate_branch(item) }
            else
              duplicate_leaf(value)
            end
          end

          def duplicate_leaf(value)
            return value if immutable_leaf?(value)

            value.dup
          end

          def immutable_leaf?(value)
            IMMUTABLE_LEAF_TYPES.any? { |type| value.is_a?(type) }
          end
        end
      end
    end
  end
end
