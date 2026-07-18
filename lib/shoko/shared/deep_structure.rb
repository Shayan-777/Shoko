# frozen_string_literal: true

module Shoko
  module Shared
    # Recursive duplication, freezing, and admission for state-value trees.
    #
    # Admissible node kinds and their treatment on write (`admit`):
    #   Hash                 — keys AND values recursively copied, frozen.
    #   Array / String       — copied, frozen.
    #   Struct               — member-copied (no initializer re-run), frozen.
    #   Data                 — rebuilt via `new(**to_h)` with copied members,
    #                          frozen. The caller's instance is untouched.
    #   Immutable primitives — nil, booleans, Symbol, Numeric: passed through.
    #   Anything else        — an opaque leaf. Opaque leaves are admitted
    #                          ONLY if already frozen; `admit` raises
    #                          otherwise. `frozen?` is the strongest check
    #                          available without reflection — value objects
    #                          must freeze their own contents in their
    #                          constructors and freeze themselves (the
    #                          state-conventions guardrail deep-verifies
    #                          this for the objects production stores).
    #
    # This is the state system's immutability primitive: the state store
    # admits every written value through `admit`, so reads can hand out
    # internals safely, and schema fragments freeze their defaults so
    # containers can share them.
    module DeepStructure
      class InadmissibleValueError < ArgumentError; end

      IMMUTABLE_PRIMITIVES = [NilClass, TrueClass, FalseClass, Symbol, Numeric].freeze

      module_function

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, inner), copy| copy[deep_dup(key)] = deep_dup(inner) }
        when Array
          value.map { |item| deep_dup(item) }
        when String
          value.frozen? ? value : value.dup
        when Struct
          duplicate_struct(value)
        when Data
          duplicate_data(value)
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

      def deep_dup_frozen(value)
        deep_freeze(deep_dup(value))
      end

      # The write-path transform for state values: copy, freeze, and verify
      # that no mutable opaque leaf slipped through. Raises
      # InadmissibleValueError for an unfrozen opaque leaf — storing it
      # would leave stored state mutable through the caller's reference.
      def admit(value)
        admitted = deep_dup_frozen(value)
        each_opaque_leaf(admitted) do |leaf|
          next if leaf.frozen?

          raise InadmissibleValueError,
                "#{leaf.class} is not admissible as a state value: opaque objects " \
                "must be frozen (value objects freeze their contents and themselves)"
        end
        admitted
      end

      # The recursable members of an admissible node, or nil for opaque
      # leaves (which are never frozen here). Hash keys are part of the
      # value: an unfrozen mutable key would corrupt the frozen hash.
      def freezable_children(value)
        case value
        when Hash then value.keys + value.values
        when Array, Struct then value.to_a
        when String then []
        when Data then value.to_h.values
        end
      end

      def each_opaque_leaf(value, &)
        case value
        when Hash
          value.each_pair do |key, inner|
            each_opaque_leaf(key, &)
            each_opaque_leaf(inner, &)
          end
        when Array, Struct
          value.each { |item| each_opaque_leaf(item, &) }
        when Data
          value.to_h.each_value { |member| each_opaque_leaf(member, &) }
        when String, *IMMUTABLE_PRIMITIVES
          nil
        else
          yield value
        end
      end

      # Struct#dup copies members shallowly without re-running a (possibly
      # keyword-only) custom initializer; members are then deep-processed in
      # the copy before it is frozen.
      def duplicate_struct(value)
        copy = value.dup
        copy.each_pair { |key, member| copy[key] = deep_dup(member) }
        copy
      end

      # Data cannot be member-assigned after allocation; rebuilding through
      # `new(**to_h)` keeps the caller's instance (and its members)
      # untouched. Data initializers in this codebase are keyword-complete
      # and idempotent normalizers, so the round-trip is value-preserving.
      def duplicate_data(value)
        value.class.new(**value.to_h.transform_values { |member| deep_dup(member) })
      end
    end
  end
end
