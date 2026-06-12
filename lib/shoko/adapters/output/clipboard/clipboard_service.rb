# frozen_string_literal: true

require_relative '../../base_adapter'
require 'shoko/shared/errors'
require 'English'

module Shoko
  module Adapters
    module Output
      module Clipboard
        # Domain service for clipboard operations with dependency injection.
        # Migrated from legacy Services::ClipboardService to follow DI pattern.
        class ClipboardService < Shoko::Adapters::BaseAdapter
          # Error raised when clipboard operations fail
          class ClipboardError < Shoko::ClipboardError; end

          # Copy text to system clipboard
          def copy_text?(text)
            return false if text.nil? || text.strip.empty?

            command = detect_copy_command
            return false unless command

            success = clipboard_write_succeeded?(command, text)

            if success
              log_success(text.length)
              true
            else
              log_failure
              false
            end
          end

          # Copy text with user feedback
          def copy_with_feedback(text)
            if copy_text?(text)
              yield(' Copied to clipboard!') if block_given?
              true
            else
              yield(' Failed to copy to clipboard') if block_given?
              false
            end
          rescue ClipboardError => e
            yield(" Copy failed: #{e.message}") if block_given?
            false
          end

          # Read text from the system clipboard.
          def read_text
            command = detect_read_command
            return nil unless command

            output = clipboard_read_output(command)
            log_read_success(output.length)
            output
          rescue SystemCallError, IOError => e
            raise ClipboardError, e.message
          end

          # Read clipboard text with user feedback.
          def read_with_feedback
            text = read_text
            if text.nil?
              yield(' Clipboard is unavailable') if block_given?
              nil
            elsif text.empty?
              yield(' Clipboard is empty') if block_given?
              nil
            else
              yield(' Pasted from clipboard') if block_given?
              text
            end
          rescue ClipboardError => e
            yield(" Paste failed: #{e.message}") if block_given?
            nil
          end

          # Check if clipboard functionality is available
          def available?
            !detect_copy_command.nil?
          end

          # Check if clipboard read functionality is available
          def read_available?
            !detect_read_command.nil?
          end

          private

          def detect_copy_command
            case RUBY_PLATFORM
            when /darwin/
              command_exists?('pbcopy') ? ['pbcopy'] : nil
            when /linux/
              if command_exists?('xclip')
                ['xclip', '-selection', 'clipboard']
              elsif command_exists?('xsel')
                ['xsel', '--clipboard', '--input']
              elsif command_exists?('wl-copy')
                ['wl-copy']
              end
            when /mswin|mingw|cygwin/
              ['clip']
            end
          end

          def detect_read_command
            case RUBY_PLATFORM
            when /darwin/
              command_exists?('pbpaste') ? ['pbpaste'] : nil
            when /linux/
              if command_exists?('xclip')
                ['xclip', '-selection', 'clipboard', '-o']
              elsif command_exists?('xsel')
                ['xsel', '--clipboard', '--output']
              elsif command_exists?('wl-paste')
                ['wl-paste']
              end
            when /mswin|mingw|cygwin/
              windows_read_command
            end
          end

          def windows_read_command
            if command_exists?('powershell.exe')
              ['powershell.exe', '-NoProfile', '-Command', 'Get-Clipboard']
            elsif command_exists?('powershell')
              ['powershell', '-NoProfile', '-Command', 'Get-Clipboard']
            end
          end

          def command_exists?(command)
            name = command.to_s.strip
            return false if name.empty?

            executable_on_path?(name)
          end

          def clipboard_write_succeeded?(command, text)
            IO.popen(command, 'w') do |pipe|
              pipe.write(text)
            end
            $CHILD_STATUS.success?
          rescue SystemCallError, IOError => e
            raise ClipboardError, e.message
          end

          def clipboard_read_output(command)
            output = IO.popen(command, 'r', &:read)
            raise ClipboardError, 'Clipboard command failed' unless $CHILD_STATUS.success?

            output.to_s
          end

          def executable_on_path?(command_name)
            path_directories.any? do |dir|
              executable_extensions.any? do |ext|
                executable_file?(dir, command_name, ext)
              end
            end
          end

          def path_directories
            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR)
          end

          def executable_extensions
            return [''] unless windows_platform?

            raw = ENV.fetch('PATHEXT', '.EXE;.BAT;.CMD')
            parsed = raw.split(';').map(&:strip).reject(&:empty?)
            (parsed + parsed.map(&:downcase) + ['']).uniq
          end

          def windows_platform?
            RUBY_PLATFORM.match?(/mswin|mingw|cygwin/i)
          end

          def executable_file?(dir, command_name, ext)
            candidate = File.join(dir, "#{command_name}#{ext}")
            File.file?(candidate) && File.executable?(candidate)
          end

          def log_success(char_count)
            logger&.info('Text copied to clipboard', chars: char_count)
          end

          def log_read_success(char_count)
            logger&.info('Text read from clipboard', chars: char_count)
          end

          def log_failure
            logger&.warn('Failed to copy text to clipboard')
          end
        end
      end
    end
  end
end
