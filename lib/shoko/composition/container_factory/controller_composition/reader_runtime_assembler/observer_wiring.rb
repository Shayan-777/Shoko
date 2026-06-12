# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          # Wires observers for reader runtime state changes.
          module ObserverWiring
            module_function

            def wire(controller:, context:)
              context.state.observer_registry.add_observer(
                controller,
                %i[reader mode],
                %i[reader dictionary_visible],
                %i[reader current_chapter],
                %i[reader single_page],
                %i[reader left_page],
                %i[reader current_page_index],
                %i[config theme],
                %i[config view_mode],
                %i[config line_spacing],
                %i[config page_numbering_mode],
                %i[config kitty_images]
              )
            end
          end
        end
      end
    end
  end
end
