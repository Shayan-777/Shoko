# frozen_string_literal: true

require_relative '../../../core/models/reader_settings'

module Shoko
  module Application
    module Services
      module Pagination
        PaginationLayoutSpec = Data.define(
          :width,
          :height,
          :view_mode,
          :line_spacing,
          :kitty_images,
          :layout_variant,
          :runtime_key,
          :cache_key
        )

        # Builds normalized pagination layout metadata for runtime and cache operations.
        class PaginationLayoutResolver
          def initialize(display_capabilities:, pagination_cache: nil)
            @display_capabilities = display_capabilities
            @pagination_cache = pagination_cache
          end

          def resolve(config_reader:, width:, height:, sidebar_visible:)
            build_layout_spec(**layout_attributes(config_reader:, width:, height:, sidebar_visible:))
          end

          def runtime_key(config_reader:, width:, height:, sidebar_visible:)
            resolve(
              config_reader: config_reader,
              width: width,
              height: height,
              sidebar_visible: sidebar_visible
            ).runtime_key
          rescue Shoko::Error
            fallback_runtime_key(width: width, height: height, sidebar_visible: sidebar_visible)
          end

          def from_cache_key(key)
            return nil unless @pagination_cache

            parsed = @pagination_cache.parse_layout_key(key)
            return nil unless parsed

            build_layout_spec(
              width: parsed[:width],
              height: parsed[:height],
              view_mode: parsed[:view_mode],
              line_spacing: parsed[:line_spacing],
              kitty_images: parsed[:kitty_images],
              layout_variant: parsed[:layout_variant],
              cache_key: key
            )
          end

          def matches_cache_key?(candidate, layout)
            return false unless @pagination_cache

            parsed = @pagination_cache.parse_layout_key(candidate)
            return false unless parsed

            parsed[:view_mode] == layout.view_mode &&
              parsed[:line_spacing] == layout.line_spacing &&
              parsed[:kitty_images] == layout.kitty_images &&
              parsed[:layout_variant] == layout.layout_variant
          end

          def layout_variant_for(config_reader:, sidebar_visible:)
            return :base unless config_reader.page_numbering_mode == :dynamic

            sidebar_visible == true ? :sidebar : :base
          end

          private

          def layout_attributes(config_reader:, width:, height:, sidebar_visible:)
            {
              width: width,
              height: height,
              view_mode: config_reader.view_mode || :single,
              line_spacing: config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING,
              kitty_images: @display_capabilities.kitty_images_enabled?(config_reader),
              layout_variant: layout_variant_for(config_reader:, sidebar_visible: sidebar_visible),
            }
          end

          def build_layout_spec(
            width:,
            height:,
            view_mode:,
            line_spacing:,
            kitty_images:,
            layout_variant:,
            cache_key: nil
          )
            attributes = {
              width: width,
              height: height,
              view_mode: view_mode,
              line_spacing: line_spacing,
              kitty_images: kitty_images,
              layout_variant: layout_variant,
            }
            PaginationLayoutSpec.new(
              **layout_spec_payload(attributes, cache_key: cache_key)
            )
          end

          def layout_spec_payload(attributes, cache_key:)
            normalized_attributes(attributes).merge(layout_keys(attributes, cache_key: cache_key))
          end

          def normalized_attributes(attributes)
            {
              width: attributes[:width].to_i,
              height: attributes[:height].to_i,
              view_mode: attributes[:view_mode],
              line_spacing: attributes[:line_spacing],
              kitty_images: attributes[:kitty_images] == true,
              layout_variant: attributes[:layout_variant],
            }
          end

          def layout_keys(attributes, cache_key:)
            {
              runtime_key: runtime_key_for(**attributes),
              cache_key: cache_key || cache_key_for(**attributes),
            }
          end

          def runtime_key_for(width:, height:, view_mode:, line_spacing:, kitty_images:, layout_variant:)
            [
              width.to_i,
              height.to_i,
              (view_mode || :single).to_sym,
              (line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING).to_sym,
              kitty_images ? 'img1' : 'img0',
              layout_variant,
            ].join(':')
          end

          def fallback_runtime_key(width:, height:, sidebar_visible:)
            [width.to_i, height.to_i, sidebar_visible == true ? :sidebar : :base].join(':')
          end

          def cache_key_for(width:, height:, view_mode:, line_spacing:, kitty_images:, layout_variant:)
            return nil unless @pagination_cache

            @pagination_cache.layout_key(
              width.to_i,
              height.to_i,
              view_mode,
              line_spacing,
              kitty_images: kitty_images == true,
              layout_variant: layout_variant
            )
          end
        end
      end
    end
  end
end
