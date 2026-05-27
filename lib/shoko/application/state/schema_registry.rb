# frozen_string_literal: true

module Shoko
  module Application
    module State
      # Composes layer-owned schema fragments into the initial runtime
      # state hash consumed by the state store.
      #
      # Each fragment is a module responding to `.contribute(context)` and
      # returning a hash keyed by partition symbol (`:reader`, `:menu`,
      # `:config`, `:ui`) whose value is the partial default hash for that
      # partition.
      #
      # The composition root constructs the registry and registers all known
      # fragments before the state store is built. Fragments are kept
      # ordered: later fragments win on key collision within the same
      # partition, allowing layered overrides if ever needed.
      class SchemaRegistry
        class FragmentContractError < StandardError; end

        def initialize
          @fragments = []
        end

        # @param fragment [#contribute] a schema fragment module
        # @return [self] for chained registration
        def register(fragment)
          validate_fragment!(fragment)
          @fragments << fragment
          self
        end

        def fragments
          @fragments.dup.freeze
        end

        # Composes the initial state hash.
        #
        # @param context [Hash] passed verbatim to each fragment's
        #   `.contribute`. Fragments that require capability detection (e.g.
        #   `Schema::Config` needs `:terminal_capabilities`) document their
        #   keys.
        # @return [Hash] the initial runtime state tree
        def initial_state(context = {})
          @fragments.each_with_object({}) do |fragment, state|
            slice = fragment.contribute(context)
            unless slice.is_a?(Hash)
              raise FragmentContractError,
                    "#{fragment} returned #{slice.class}; expected Hash keyed by partition"
            end

            slice.each do |partition, defaults|
              state[partition] ||= {}
              state[partition].merge!(defaults)
            end
          end
        end

        private

        # Verifies the fragment exposes `#contribute(context)` via direct
        # method lookup rather than reflective probing, satisfying the
        # strict-migration reflection ban while still failing fast at
        # registration time on malformed fragments.
        def validate_fragment!(fragment)
          fragment.method(:contribute)
        rescue NameError
          raise FragmentContractError, "#{fragment} must define #contribute(context)"
        end
      end
    end
  end
end
