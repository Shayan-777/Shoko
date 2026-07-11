# frozen_string_literal: true

require 'digest/sha1'

require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/terminal/kitty_unicode_placeholders'
require_relative '../../components/render_style'
require_relative 'config_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Renders DisplayLine image metadata using Kitty graphics placeholders.
          #
          # This object is created per render frame and uses a per-frame dedupe cache to avoid
          # repeated `prepare_virtual` calls for the same image placement.
          class KittyImageLineRenderer
            RenderRequest = Struct.new(:meta,
                                       :render_opts,
                                       :src,
                                       :cols,
                                       :rows,
                                       :col_offset,
                                       :line_index,
                                       :chapter_entry)

            def initialize(dependencies:, placed_kitty_images:)
              @dependencies = dependencies
              @placed_kitty_images = placed_kitty_images
            end

            def kitty_image_line?(line, config:)
              meta = metadata_hash(line)
              return false unless meta
              return false unless enabled?(config)

              render_opts = image_render_options(meta)
              return false unless render_opts

              !image_src(meta).to_s.strip.empty?
            end

            def render(line, context)
              request = render_request_for(line)
              return [nil, 0] unless request

              placement_id = placement_id_for(render_opts: request.render_opts,
                                              chapter_entry: request.chapter_entry,
                                              src: request.src,
                                              cols: request.cols,
                                              rows: request.rows)
              placeholder = placeholder_for_request(context, request, placement_id)
              return [placeholder, request.col_offset] if placeholder

              fallback_for(request.meta, request.cols, request.col_offset)
            end

            private

            def render_request_for(line)
              meta, render_opts = meta_and_render_options(line)
              return nil unless meta && render_opts

              src = src_for_request(meta)
              return nil unless src

              build_render_request(meta, render_opts, src)
            end

            def placeholder_for_request(context, request, placement_id)
              prepared_id = prepared_id_for(context: context,
                                            chapter_entry: request.chapter_entry,
                                            src: request.src,
                                            cols: request.cols,
                                            rows: request.rows,
                                            placement_id: placement_id)
              return nil unless prepared_id

              placeholder_for(prepared_id, placement_id, request.cols, request.line_index)
            end

            def metadata_hash(line)
              meta = line.metadata
              meta.is_a?(Hash) ? meta : nil
            end

            def enabled?(config)
              !!config.kitty_images
            end

            def image_render_options(meta)
              render_opts = meta[:image_render]
              render_opts.is_a?(Hash) ? render_opts : nil
            end

            def image_src(meta)
              image = meta[:image] || {}
              image[:src]
            end

            def integer_or_zero(value)
              value.to_i
            end

            def meta_and_render_options(line)
              meta = metadata_hash(line)
              return [nil, nil] unless meta

              [meta, image_render_options(meta)]
            end

            def src_for_request(meta)
              src = image_src(meta).to_s.strip
              src.empty? ? nil : src
            end

            def build_render_request(meta, render_opts, src)
              RenderRequest.new(
                meta: meta,
                render_opts: render_opts,
                src: src,
                cols: integer_or_zero(render_opts[:cols]),
                rows: integer_or_zero(render_opts[:rows]),
                col_offset: integer_or_zero(render_opts[:col_offset]),
                line_index: integer_or_zero(meta[:image_line_index]),
                chapter_entry: meta[:chapter_source_path]
              )
            end

            def placement_id_for(render_opts:, chapter_entry:, src:, cols:, rows:)
              raw = integer_or_zero(render_opts[:placement_id])
              return normalize_placement_id(raw) if raw.positive?

              seed = placement_seed(chapter_entry, src, cols, rows)
              normalize_placement_id(Digest::SHA1.digest(seed).unpack1('N'))
            end

            def placement_seed(chapter_entry, src, cols, rows)
              core = core_src(src)
              "#{chapter_entry}|#{core}|#{cols}|#{rows}"
            end

            def core_src(src)
              src.to_s.split(/[?#]/, 2).first.to_s
            end

            def normalize_placement_id(raw)
              value = raw.to_i & 0xFF_FF_FF
              value.zero? ? 1 : value
            end

            def prepared_id_for(context:, chapter_entry:, src:, cols:, rows:, placement_id:)
              dedupe = dedupe_key(chapter_entry:, src:, cols:, rows:, placement_id:)
              prepared = cached_prepared_id(dedupe)
              return prepared if prepared

              prepared = prepare_virtual(context:, chapter_entry:, src:, cols:, rows:, placement_id:)
              cache_prepared_id(dedupe, prepared)
              prepared
            end

            def dedupe_key(chapter_entry:, src:, cols:, rows:, placement_id:)
              core = core_src(src)
              "#{chapter_entry}|#{core}|#{cols}|#{rows}|p=#{placement_id}"
            end

            def cached_prepared_id(dedupe_key)
              return nil unless dedupe_key && @placed_kitty_images.is_a?(Hash)

              cached = @placed_kitty_images[dedupe_key]
              return cached if cached.is_a?(Integer)

              nil
            end

            def cache_prepared_id(dedupe_key, prepared_id)
              return unless dedupe_key && @placed_kitty_images.is_a?(Hash)

              @placed_kitty_images[dedupe_key] = prepared_id || false
            end

            def prepare_virtual(context:, chapter_entry:, src:, cols:, rows:, placement_id:)
              renderer = kitty_image_renderer
              return nil unless renderer

              renderer.prepare_virtual(
                **prepare_virtual_args(
                  context: context,
                  chapter_entry: chapter_entry,
                  src: src,
                  cols: cols,
                  rows: rows,
                  placement_id: placement_id
                )
              )
            end

            def prepare_virtual_args(context:, chapter_entry:, src:, cols:, rows:, placement_id:)
              doc = context&.document
              {
                output: @dependencies.terminal_output,
                book_sha: doc&.cache_sha,
                epub_path: doc&.canonical_path,
                chapter_entry_path: chapter_entry,
                src: src,
                cols: cols,
                rows: rows,
                placement_id: placement_id,
                z: -1,
              }
            end

            def placeholder_for(prepared_id, placement_id, cols, line_index)
              cols_i = cols.to_i
              line_i = line_index.to_i
              return nil unless cols_i.between?(1, 255) && line_i.between?(0, 255)

              grid = (line_i << 8) | cols_i
              Shoko::Shared::Terminal::KittyUnicodePlaceholders.line(
                image_id: prepared_id,
                placement_id: placement_id,
                grid: grid
              )
            end

            def fallback_for(meta, cols, col_offset)
              render_line = meta.key?(:image_render_line) ? meta[:image_render_line] : meta['image_render_line']
              return ['', col_offset] unless render_line == true

              plain = '[Image]'
              clipped = if cols.to_i.positive?
                          Shoko::Shared::Terminal::TextMetrics.truncate_to(plain, cols.to_i)
                        else
                          plain
                        end
              [Shoko::Adapters::Ui::Components::RenderStyle.dim(clipped), col_offset]
            end

            def kitty_image_renderer
              @kitty_image_renderer ||= @dependencies.kitty_image_renderer
            end
          end
        end
      end
    end
  end
end
