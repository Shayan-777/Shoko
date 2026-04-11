# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Centralized icon lookup with optional ASCII fallback for limited fonts.
          module IconSet
            ICONS = {
              browse: '󱉟',
              library: '',
              annotations: '',
              rss_reader: '󰑫',
              download: '',
              translator: '󰗊',
              settings: '',
              quit: '',
              back: '',
              view_mode: '',
              line_spacing: '',
              theme: '󰉦',
              page_mode: '',
              page_numbers: '',
              highlight: '',
              dictionary: '',
              images: '',
              wipe: '',
              checkbox: '',
            }.freeze

            ASCII = {
              browse: '[B]',
              library: '[L]',
              annotations: '[A]',
              rss_reader: '[RSS]',
              download: '[D]',
              translator: '[Tr]',
              settings: '[S]',
              quit: '[Q]',
              back: '<-',
              view_mode: '[V]',
              line_spacing: '[LS]',
              theme: '[Th]',
              page_mode: '[PM]',
              page_numbers: '[#]',
              highlight: '[H]',
              dictionary: '[Dict]',
              images: '[Img]',
              wipe: '[!]',
              checkbox: '',
            }.freeze

            module_function

            def icon_for(key)
              return ASCII[key].to_s if ascii_icons?

              ICONS[key].to_s
            end

            def selection_pointer
              ascii_icons? ? '> ' : '▸ '
            end

            def ascii_icons?
              val = ENV.fetch('SHOKO_ASCII_ICONS', '').to_s.strip.downcase
              %w[1 true yes on].include?(val)
            end
          end
        end
      end
    end
  end
end
