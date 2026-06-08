# frozen_string_literal: true

require_relative 'controller_assembly/sidebar_builder'
require_relative 'controller_assembly/dictionary_builder'
require_relative 'controller_assembly/overlay_builder'
require_relative 'controller_assembly/ui_builder'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              # Builds sidebar/dictionary/search/annotation/ui controllers.
              module ControllerAssembly
                module_function

                def build_sidebar_controller(build_context)
                  SidebarBuilder.build(build_context)
                end

                def build_dictionary_controller(build_context)
                  DictionaryBuilder.build(build_context)
                end

                def build_annotation_controller(build_context)
                  OverlayBuilder.build_annotation(build_context)
                end

                def build_in_book_search_controller(build_context)
                  OverlayBuilder.build_in_book_search(build_context)
                end

                def build_toc_controller(build_context)
                  OverlayBuilder.build_toc(build_context)
                end

                def build_translator_controller(build_context)
                  OverlayBuilder.build_translator(build_context)
                end

                def build_notes_controller(build_context)
                  OverlayBuilder.build_notes(build_context)
                end

                def build_ui_controller(build_context, controller_set)
                  UiBuilder.build(build_context, controller_set)
                end
              end
            end
          end
        end
      end
    end
  end
end
