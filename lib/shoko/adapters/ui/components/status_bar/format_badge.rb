# frozen_string_literal: true

require_relative 'palette'

module Shoko
  module Adapters
    module Ui
      module Components
        module StatusBar
          # Resolves a file format into a colored status-bar badge.
          #
          # Color is assigned by format family (per the product spec):
          #   epub -> green, pdf -> red, rtf -> blue, kindle -> orange, fb2 -> purple
          # while the label keeps the precise extension (EPUB, PDF, AZW3, MOBI, ...).
          #
          # This is a presentation concern, so the extension->family mapping lives
          # here in the UI rather than coupling to the book-source adapter.
          module FormatBadge
            # A renderable badge: short label on a colored pill.
            # +rgb+ is the pill background; +fg+ is the (already light/dark balanced)
            # text color. When +mode+ is set the bar draws a second, neutral
            # compartment ("Reader"/"Search") joined to the format pill by a tilted slant.
            Badge = Data.define(:label, :rgb, :fg, :mode)

            # Extension (without dot) -> color family.
            FAMILY_BY_EXTENSION = {
              epub: :epub,
              pdf: :pdf,
              fb2: :fb2,
              mobi: :kindle,
              azw: :kindle,
              azw3: :kindle,
              kf8: :kindle,
              rtf: :rtf,
            }.freeze

            DARK_TEXT = [22, 25, 33].freeze
            LIGHT_TEXT = [248, 250, 255].freeze

            # Family -> { rgb: pill background, fg: balanced text color }.
            FAMILY_COLORS = {
              epub: { rgb: [63, 185, 80], fg: DARK_TEXT },
              pdf: { rgb: [240, 90, 82], fg: LIGHT_TEXT },
              rtf: { rgb: [56, 139, 253], fg: LIGHT_TEXT },
              kindle: { rgb: [229, 148, 58], fg: DARK_TEXT },
              fb2: { rgb: [188, 140, 255], fg: DARK_TEXT },
            }.freeze

            DEFAULT_COLOR = { rgb: [120, 127, 156], fg: LIGHT_TEXT }.freeze

            module_function

            # Build a badge for a format extension symbol (e.g. :epub, :azw3).
            # Returns nil when the format is unknown/blank so callers can omit it.
            def for_format(extension)
              ext = normalize(extension)
              return nil unless ext

              family = FAMILY_BY_EXTENSION[ext] || ext
              color = FAMILY_COLORS[family] || DEFAULT_COLOR
              Badge.new(label: ext.to_s.upcase, rgb: color[:rgb], fg: color[:fg], mode: nil)
            end

            # Derive the format extension symbol from a file path.
            # Handles the compound `.fb2.zip` case; returns nil when unrecognized.
            def format_for_path(path)
              lower = path.to_s.strip.downcase
              return nil if lower.empty?
              return :fb2 if lower.end_with?('.fb2.zip')

              ext = File.extname(lower).delete_prefix('.')
              ext.empty? ? nil : ext.to_sym
            end

            # A two-compartment reader badge: a neutral "mode" compartment
            # (Reader / Search) joined to the format-colored compartment by a
            # tilted slant. The format compartment keeps the format's color and
            # shows the lowercase extension. Falls back to a single brand badge
            # when the format is unknown.
            def mode_badge(mode, extension)
              mode_text = mode.to_s.strip
              ext = normalize(extension)
              return view_badge(mode_text) unless ext

              base = for_format(ext)
              Badge.new(label: ext.to_s, rgb: base.rgb, fg: base.fg, mode: mode_text)
            end

            # A neutral, brand-accented badge for non-reader views (menus, lists).
            def view_badge(label)
              text = label.to_s.strip.upcase
              return nil if text.empty?

              Badge.new(label: text, rgb: Palette::BRAND_RGB, fg: DARK_TEXT, mode: nil)
            end

            def normalize(extension)
              return nil if extension.nil?

              sym = extension.to_s.strip.downcase.delete_prefix('.').to_sym
              sym.empty? ? nil : sym
            end
          end
        end
      end
    end
  end
end
