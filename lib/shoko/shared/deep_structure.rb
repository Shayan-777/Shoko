# frozen_string_literal: true

module Shoko
  module Shared
    # Recursive duplication and freezing for state-admissible data trees.
    #
    # Admissible node kinds and their treatment:
    #   Hash / Array / String — duplicated on write, frozen.
    #   Struct               — member-copied (no initializer re-run), members
    #                          recursively processed, frozen.
    #   Data                 — already per-instance immutable; the instance
    #                          and its members are frozen in place (a Data is
    #                          a value object: its members ARE the value, so
    #                          they are not caller-owned scratch space).
    #   Anything else        — an opaque leaf, passed through untouched. The
    #                          state contract requires such leaves to be
    #                          effectively immutable (no public writers); the
    #                          state-conventions guardrail enforces this.
    #
    # This is the state system's immutability primitive: the state store
    # deep-freezes its tree so reads can hand out internals safely, and
    # schema fragments freeze their defaults so containers can share them.
    module DeepStructure
      module_function

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, inner), copy| copy[key] = deep_dup(inner) }
        when Array
          value.map { |item| deep_dup(item) }
        when String
          value.frozen? ? value : value.dup
        when Struct
          duplicate_struct(value)
        else
          value
        end
      end

      def deep_freeze(value)
        children = freezable_children(value)
        return value unless children

        children.each { |child| deep_freeze(child) }
        value.freeze
      end

      # The recursable members of an admissible node, or nil for opaque
      # leaves (which are never frozen here).
      def freezable_children(value)
        case value
        when Hash then value.values
        when Array, Struct then value.to_a
        when String then []
        when Data then value.to_h.values
        end
      end

      def deep_dup_frozen(value)
        deep_freeze(deep_dup(value))
      end

      # Struct#dup copies members shallowly without re-running a (possibly
      # keyword-only) custom initializer; members are then deep-processed in
      # the copy before it is frozen.
      def duplicate_struct(value)
        copy = value.dup
        copy.each_pair { |key, member| copy[key] = deep_dup(member) }
        copy
      end
    end
  end
end
