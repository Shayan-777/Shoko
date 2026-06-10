# frozen_string_literal: true

require 'rexml/document'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Small REXML traversal helpers for EPUB navigation documents.
        module OPFElementNameHelpers
          private

          def element_name?(element, *names)
            return false unless element.is_a?(REXML::Element)

            names.any? { |name| element.name.to_s.casecmp(name.to_s).zero? }
          end

          def attribute_value(element, *names)
            attribute_values(element, *names).first
          end

          def attribute_values(element, *names)
            return [] unless element.is_a?(REXML::Element)

            normalized_names = names.map { |name| name.to_s.downcase }
            element.attributes.each_attribute.each_with_object([]) do |attribute, values|
              values << attribute.value if attribute_name_matches?(attribute, normalized_names)
            end
          end

          def first_child_element_named(element, *names)
            each_child_element(element) do |child|
              return child if element_name?(child, *names)
            end
            nil
          end

          def first_descendant_element_named(element, *names)
            each_descendant_element(element) do |child|
              return child if element_name?(child, *names)
            end
            nil
          end

          def each_child_element(element, &)
            return enum_for(:each_child_element, element) unless block_given?
            return unless element.is_a?(REXML::Element)

            element.elements.each(&)
          end

          def each_descendant_element(element, &block)
            return enum_for(:each_descendant_element, element) unless block

            each_child_element(element) do |child|
              yield(child)
              each_descendant_element(child, &block)
            end
          end

          def each_element_including_root(root, &)
            return enum_for(:each_element_including_root, root) unless block_given?
            return unless root.is_a?(REXML::Element)

            yield root
            each_descendant_element(root, &)
          end

          def attribute_name_matches?(attribute, normalized_names)
            [attribute.name, attribute.expanded_name].any? do |name|
              normalized_names.include?(name.to_s.downcase)
            end
          end
        end
      end
    end
  end
end
