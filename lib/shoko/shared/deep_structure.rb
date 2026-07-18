# frozen_string_literal: true

module Shoko
  module Shared
    # The closed value contract used by the immutable state tree.
    #
    # Admissible values are deliberately limited to plain data:
    #   * intrinsic immutable primitives (nil, booleans, symbols, and the
    #     built-in numeric value classes);
    #   * exact String, Array, and Hash instances;
    #   * Struct and Data value objects whose complete state is represented by
    #     their declared members.
    #
    # Containers, Hash keys, and value-object members are recursively copied
    # and frozen. Arbitrary opaque objects are rejected even when their outer
    # object is frozen: Object#frozen? says nothing about mutable state reachable
    # through that object. Cycles and Hashes with non-plain lookup semantics are
    # rejected explicitly rather than failing with SystemStackError or silently
    # changing meaning during the copy.
    module DeepStructure
      class InadmissibleValueError < ArgumentError; end

      IMMUTABLE_PRIMITIVE_CLASSES = [
        NilClass,
        TrueClass,
        FalseClass,
        Symbol,
        Integer,
        Float,
        Rational,
        Complex,
      ].freeze

      module_function

      # State-facing entry point. The returned graph shares no mutable
      # structure with +value+ and has been independently verified against the
      # same closed contract used to build it.
      def admit(value)
        admitted = copy_admissible(value, active: {}.compare_by_identity)
        verify_admitted!(admitted, active: {}.compare_by_identity, seen: {}.compare_by_identity)
        admitted
      end

      # Kept as the descriptive API used by snapshot construction. State data
      # has one contract, so this is intentionally identical to admission.
      def deep_dup_frozen(value) = admit(value)

      def copy_admissible(value, active:)
        return value if immutable_primitive?(value)

        case value
        when String then copy_string(value)
        when Hash then copy_hash(value, active: active)
        when Array then copy_array(value, active: active)
        when Struct then copy_struct(value, active: active)
        when Data then copy_data(value, active: active)
        else raise_inadmissible!(value, 'opaque objects are not state values')
        end
      end
      private_class_method :copy_admissible

      def copy_string(value)
        require_exact_class!(value, String)
        require_unadorned_value!(value)
        String.new(value).freeze
      end
      private_class_method :copy_string

      def copy_hash(value, active:)
        require_exact_class!(value, Hash)
        require_unadorned_value!(value)
        require_plain_hash!(value)
        with_cycle_guard(value, active) do
          copy = {}
          Hash.instance_method(:each_pair).bind_call(value) do |key, inner|
            copy[copy_admissible(key, active: active)] = copy_admissible(inner, active: active)
          end
          copy.freeze
        end
      end
      private_class_method :copy_hash

      def copy_array(value, active:)
        require_exact_class!(value, Array)
        require_unadorned_value!(value)
        with_cycle_guard(value, active) do
          copy = []
          Array.instance_method(:each).bind_call(value) do |item|
            copy << copy_admissible(item, active: active)
          end
          copy.freeze
        end
      end
      private_class_method :copy_array

      def copy_struct(value, active:)
        require_member_only_value!(value)
        with_cycle_guard(value, active) do
          copy = Object.instance_method(:dup).bind_call(value)
          Struct.instance_method(:each_pair).bind_call(value) do |key, member|
            Struct.instance_method(:[]=).bind_call(copy, key, copy_admissible(member, active: active))
          end
          copy.freeze
        end
      end
      private_class_method :copy_struct

      def copy_data(value, active:)
        require_member_only_value!(value)
        with_cycle_guard(value, active) do
          attributes = raw_data_members(value).transform_values do |member|
            copy_admissible(member, active: active)
          end
          Class.instance_method(:new).bind_call(intrinsic_class(value), **attributes)
        rescue ArgumentError, TypeError => e
          raise InadmissibleValueError,
                "#{value.class} cannot be rebuilt from its declared Data members: #{e.message}"
        end
      end
      private_class_method :copy_data

      # Bypass domain serialization overrides of #to_h. Data's own method is
      # the canonical member map; e.g. ReadingProgress#to_h intentionally uses
      # the persisted key :chapter instead of its member :chapter_index.
      def raw_data_members(value)
        Data.instance_method(:to_h).bind_call(value)
      end
      private_class_method :raw_data_members

      def immutable_primitive?(value)
        IMMUTABLE_PRIMITIVE_CLASSES.include?(intrinsic_class(value))
      end
      private_class_method :immutable_primitive?

      def require_exact_class!(value, expected)
        return if intrinsic_class(value).equal?(expected)

        raise_inadmissible!(value, "subclasses of #{expected} may carry hidden mutable state")
      end
      private_class_method :require_exact_class!

      def require_member_only_value!(value)
        require_unadorned_value!(value)
      end
      private_class_method :require_member_only_value!

      # Exact built-in classes can still carry instance variables or singleton
      # behavior. Either would be state outside the traversed container/member
      # graph, so reject it rather than copying only the visible portion.
      def require_unadorned_value!(value)
        instance_variables = Object.instance_method(:instance_variables).bind_call(value)
        singleton_methods = Object.instance_method(:singleton_methods).bind_call(value)
        return if instance_variables.empty? && singleton_methods.empty?

        raise_inadmissible!(value, 'values may contain only their declared elements or members')
      end
      private_class_method :require_unadorned_value!

      def require_plain_hash!(value)
        return if value.default_proc.nil? && value.default.nil? && !value.compare_by_identity?

        raise_inadmissible!(value, 'state Hashes must have nil defaults and equality-based keys')
      end
      private_class_method :require_plain_hash!

      def with_cycle_guard(value, active)
        raise_inadmissible!(value, 'cyclic value graphs are not admissible') if active.key?(value)

        active[value] = true
        yield
      ensure
        active.delete(value)
      end
      private_class_method :with_cycle_guard

      def verify_admitted!(value, active:, seen:)
        return value if immutable_primitive?(value)

        raise_inadmissible!(value, 'cyclic value graphs are not admissible') if active.key?(value)
        return value if seen.key?(value)

        frozen = Object.instance_method(:frozen?).bind_call(value)
        raise_inadmissible!(value, 'admitted values must be frozen') unless frozen

        seen[value] = true
        children = admitted_children(value)
        verify_children!(value, children, active: active, seen: seen)
        value
      end
      private_class_method :verify_admitted!

      def admitted_children(value)
        case value
        when String then verified_string_children(value)
        when Hash then verified_hash_children(value)
        when Array then verified_array_children(value)
        when Struct then verified_struct_children(value)
        when Data then verified_data_children(value)
        else raise_inadmissible!(value, 'opaque objects are not state values')
        end
      end
      private_class_method :admitted_children

      def verified_string_children(value)
        require_exact_class!(value, String)
        require_unadorned_value!(value)
        []
      end
      private_class_method :verified_string_children

      def verified_hash_children(value)
        require_exact_class!(value, Hash)
        require_unadorned_value!(value)
        require_plain_hash!(value)
        children = []
        Hash.instance_method(:each_pair).bind_call(value) { |key, inner| children.push(key, inner) }
        children
      end
      private_class_method :verified_hash_children

      def verified_array_children(value)
        require_exact_class!(value, Array)
        require_unadorned_value!(value)
        children = []
        Array.instance_method(:each).bind_call(value) { |child| children << child }
        children
      end
      private_class_method :verified_array_children

      def verified_struct_children(value)
        require_member_only_value!(value)
        raw_struct_members(value)
      end
      private_class_method :verified_struct_children

      def verified_data_children(value)
        require_member_only_value!(value)
        raw_data_members(value).values
      end
      private_class_method :verified_data_children

      def verify_children!(owner, children, active:, seen:)
        with_cycle_guard(owner, active) do
          children.each { |child| verify_admitted!(child, active: active, seen: seen) }
        end
      end
      private_class_method :verify_children!

      def raise_inadmissible!(value, reason)
        raise InadmissibleValueError, "#{intrinsic_class(value)} is not admissible as a state value: #{reason}"
      end
      private_class_method :raise_inadmissible!

      def raw_struct_members(value)
        members = []
        Struct.instance_method(:each_pair).bind_call(value) { |_key, member| members << member }
        members
      end
      private_class_method :raw_struct_members

      def intrinsic_class(value) = Object.instance_method(:class).bind_call(value)
      private_class_method :intrinsic_class
    end
  end
end
