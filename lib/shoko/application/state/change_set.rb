# frozen_string_literal: true

module Shoko
  module Application
    module State
      class StateStore
        # Immutable set of changed state paths produced by a committed update.
        class ChangeSet
          include Enumerable

          # Immutable value object describing a single changed state path.
          Change = Data.define(:path, :old_value, :new_value)

          class << self
            def build(root_before:, root_after:, updates:)
              changes = updates.each_with_object([]) do |(path, _value), acc|
                normalized_path = Array(path).dup.freeze
                old_value = nested_value(root_before, normalized_path)
                new_value = nested_value(root_after, normalized_path)
                next if old_value == new_value

                acc << Change.new(path: normalized_path, old_value: old_value, new_value: new_value)
              end

              new(changes: changes, root: root_after)
            end

            private

            def nested_value(hash, path)
              path.reduce(hash) { |node, key| node&.dig(key) }
            end
          end

          attr_reader :root

          def initialize(changes:, root:)
            @changes = Array(changes).freeze
            @root = root
          end

          def each(&)
            @changes.each(&)
          end

          def empty?
            @changes.empty?
          end

          def size
            @changes.size
          end
        end
      end
    end
  end
end
