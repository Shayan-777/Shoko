# frozen_string_literal: true

require 'base64'

module Shoko
  module Adapters
    module Output
      module Kitty
        # Minimal support for the Kitty graphics protocol.
        #
        # This module intentionally keeps all logic in-process (no external commands)
        # and suppresses terminal responses (q=2) to avoid corrupting raw input reads.
        module KittyGraphics
          module_function

          ESC = "\e"
          APC_START = "#{ESC}_G".freeze
          APC_END = "#{ESC}\\".freeze
          MAX_CHUNK_BYTES = 4096
          SUPPORTED_TERM_PROGRAMS = %w[kitty ghostty].freeze

          def supported?
            return true if env_present?('KITTY_WINDOW_ID')
            return true if terminal_name.include?('kitty')
            return true if terminal_name.include?('ghostty')
            return true if SUPPORTED_TERM_PROGRAMS.include?(terminal_program)

            false
          end

          # Defensive on the config contract: any object reaching the wrap path
          # that does not expose #kitty_images simply disables images rather than
          # raising NoMethodError up into the reader's render loop. The reader's
          # real config reader always responds; a mis-wired or stub config must
          # never be able to take down rendering.
          def enabled_for?(config_reader)
            return false unless supported?
            return false unless config_reader.respond_to?(:kitty_images)

            !!config_reader.kitty_images
          end

          def transmit_png(image_id, png_bytes, quiet: true)
            bytes = String(png_bytes).dup
            bytes.force_encoding(Encoding::BINARY)
            payload = Base64.strict_encode64(bytes)
            chunks = chunk_payload(payload)
            chunks.map.with_index do |chunk, index|
              more = index < chunks.length - 1 ? 1 : 0
              keys = if index.zero?
                       { a: 't', f: 100, t: 'd', i: image_id.to_i, m: more }
                     else
                       { m: more }
                     end
              keys[:q] = 2 if quiet
              control = serialize_keys(keys)
              "#{APC_START}#{control};#{chunk}#{APC_END}"
            end
          end

          def place(image_id, placement_id:, cols:, rows:, quiet: true, **options)
            z = options.fetch(:z, nil)
            keys = { a: 'p', i: image_id.to_i, p: placement_id.to_i, c: cols.to_i, r: rows.to_i, C: 1 }
            keys[:q] = 2 if quiet
            keys[:z] = z.to_i if z
            "#{APC_START}#{serialize_keys(keys)}#{APC_END}"
          end

          def virtual_place(image_id, cols:, rows:, placement_id: nil, quiet: true, **options)
            z = options.fetch(:z, nil)
            keys = { a: 'p', U: 1, i: image_id.to_i, p: placement_id.to_i, c: cols.to_i, r: rows.to_i, C: 1 }
            keys.delete(:p) if placement_id.to_i <= 0
            keys[:q] = 2 if quiet
            keys[:z] = z.to_i if z
            "#{APC_START}#{serialize_keys(keys)}#{APC_END}"
          end

          def delete_visible(quiet: true)
            keys = { a: 'd' }
            keys[:q] = 2 if quiet
            "#{APC_START}#{serialize_keys(keys)}#{APC_END}"
          end

          def chunk_payload(payload)
            return [] if payload.nil? || payload.empty?

            max = MAX_CHUNK_BYTES
            payload.scan(/.{1,#{max}}/m)
          end
          private_class_method :chunk_payload

          def serialize_keys(hash)
            hash.map { |k, v| "#{k}=#{v}" }.join(',')
          end
          private_class_method :serialize_keys

          def env_present?(key)
            value = ENV[key].to_s
            !value.empty?
          end
          private_class_method :env_present?

          def terminal_name
            ENV.fetch('TERM', '').downcase
          end
          private_class_method :terminal_name

          def terminal_program
            ENV.fetch('TERM_PROGRAM', '').downcase
          end
          private_class_method :terminal_program
        end
      end
    end
  end
end
