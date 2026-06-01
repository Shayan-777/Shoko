# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Stateless deep-duplication of a requested state subtree for snapshot
        # materialization. A pure collaborator (no instance state) shared by the
        # session-state store adapters; called as `BranchSnapshot.duplicate_fields`
        # / `BranchSnapshot.duplicate_branch`. Formerly the BranchSnapshotSupport
        # mixin (audit ARCH-3).
        module BranchSnapshot
          IMMUTABLE_LEAF_TYPES = [NilClass, TrueClass, FalseClass, Numeric, Symbol].freeze

          module_function

          def duplicate_fields(source, fields)
            Array(fields).to_h do |field|
              [field, duplicate_branch(source[field])]
            end
          end

          def duplicate_branch(value)
            case value
            when Hash
              value.transform_values do |inner_value|
                duplicate_branch(inner_value)
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
