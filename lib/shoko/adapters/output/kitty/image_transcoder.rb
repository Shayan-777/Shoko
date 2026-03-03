# frozen_string_literal: true

require 'open3'

module Shoko
  module Adapters
    module Output
      module Kitty
        # Converts common raster image formats to PNG bytes so they can be rendered
        # by the Kitty graphics protocol.
        #
        # This is invoked only when Kitty images are enabled and an image is about
        # to be rendered; it is not part of the default import pipeline.
        class ImageTranscoder
          PNG_HEADER = "\x89PNG\r\n\x1a\n".b

          def initialize(command: nil)
            @command = command || default_command
          end

          def available?
            !@command.nil?
          end

          # @param bytes [String] original image bytes
          # @return [String,nil] PNG bytes
          def to_png(bytes)
            data = String(bytes).dup
            data.force_encoding(Encoding::BINARY)
            return nil if data.empty?
            return data if png?(data)
            return nil unless available?

            stdout, _stderr, status = Open3.capture3(*@command, stdin_data: data)
            return nil unless status.success?

            out = String(stdout).dup
            out.force_encoding(Encoding::BINARY)
            return nil unless png?(out)

            out
          rescue Shoko::Error
            nil
          end

          private

          def png?(bytes)
            bytes.to_s.b.start_with?(PNG_HEADER)
          rescue Shoko::Error
            false
          end

          def default_command
            return ['magick', '-', 'png:-'] if executable_in_path?('magick')
            return ['convert', '-', 'png:-'] if executable_in_path?('convert')

            nil
          end

          def executable_in_path?(name)
            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
              next false if dir.to_s.empty?

              path = File.join(dir, name)
              File.file?(path) && File.executable?(path)
            end
          rescue Shoko::Error
            false
          end
        end
      end
    end
  end
end
