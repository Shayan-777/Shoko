# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module CommandFactory
        # Reads and writes the menu/reader state used by shared command lambdas.
        module StateAccess
          MENU_NUMERIC_FIELDS = {
            selected: :selected,
            browse_selected: :browse_selected,
            settings_selected: :settings_selected,
            download_selected: :download_selected,
            dictionary_selected: :dictionary_selected,
            search_cursor: :search_cursor,
            download_cursor: :download_cursor,
            dictionary_cursor: :dictionary_cursor,
          }.freeze

          MENU_TEXT_FIELDS = {
            search_query: :search_query,
            download_query: :download_query,
            dictionary_query: :dictionary_query,
          }.freeze

          READER_NUMERIC_FIELDS = {
            sidebar_toc_selected: :sidebar_toc_selected,
            sidebar_bookmarks_selected: :sidebar_bookmarks_selected,
            sidebar_annotations_selected: :sidebar_annotations_selected,
          }.freeze

          module_function

          def dispatch_for(ctx, action_type, field, value)
            case action_type
            when :menu
              dispatch_menu(ctx, field => value)
            when :sidebar
              resolve_reader_session_mutator(ctx).update_sidebar(field => value)
            end
          end

          def dispatch_menu(ctx, hash)
            resolve_menu_session_mutator(ctx).update_menu(hash)
          end

          def value_at(ctx, base, field)
            case base
            when :menu
              menu_numeric_value(resolve_menu_state_reader(ctx), field)
            when :reader
              reader_numeric_value(resolve_reader_state_reader(ctx), field)
            else
              0
            end
          end

          def current_value(ctx, input_path)
            return '' unless input_path&.length == 2

            base, field = input_path
            return '' unless base == :menu

            menu_text_value(resolve_menu_state_reader(ctx), field)
          end

          def menu_numeric_value(reader, field)
            numeric_value(reader, field, MENU_NUMERIC_FIELDS, 'menu numeric')
          end

          def menu_text_value(reader, field)
            text_value(reader, field, MENU_TEXT_FIELDS, 'menu text')
          end

          def reader_numeric_value(reader, field)
            numeric_value(reader, field, READER_NUMERIC_FIELDS, 'reader numeric')
          end

          def resolve_menu_state_reader(ctx)
            ctx.menu_state_reader
          end

          def resolve_menu_session_mutator(ctx)
            ctx.menu_session_mutator
          end

          def resolve_reader_session_mutator(ctx)
            ctx.reader_session_mutator
          end

          def resolve_reader_state_reader(ctx)
            ctx.reader_state_reader
          end

          def numeric_value(reader, field, mapping, label)
            method_name = mapping[field.to_sym]
            raise ArgumentError, "Unsupported #{label} field: #{field}" unless method_name

            reader.public_send(method_name).to_i
          end
          private_class_method :numeric_value

          def text_value(reader, field, mapping, label)
            method_name = mapping[field.to_sym]
            raise ArgumentError, "Unsupported #{label} field: #{field}" unless method_name

            reader.public_send(method_name).to_s
          end
          private_class_method :text_value
        end
      end
    end
  end
end
