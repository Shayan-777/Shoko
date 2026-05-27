# frozen_string_literal: true

require_relative 'menu_transient_snapshot'

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Splits menu updates across the durable session slice and the
          # transient workflow slice, based on which schema fragment owns
          # each field. Lives with the port snapshot contracts so both
          # adapter mutators and application workflows can use it.
          module MenuStatePartition
            module_function

            def split(attributes)
              transient_fields = MenuTransientSnapshot::FIELDS
              attributes.each_with_object([{}, {}]) do |(field, value), targets|
                session_attributes, transient_attributes = targets
                if transient_fields.include?(field)
                  transient_attributes[field] = value
                else
                  session_attributes[field] = value
                end
              end
            end
          end
        end
      end
    end
  end
end
