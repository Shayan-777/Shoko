# frozen_string_literal: true

require_relative 'input_command_payload'

module Shoko
  module Application
    module UseCases
      module Commands
        # Enhanced base command with proper error handling and validation.
        # Replaces the mixed command patterns with consistent implementation.
        class BaseCommand
          # Base error type for command execution and validation failures.
          class CommandError < StandardError
            attr_reader :command_name, :context

            def initialize(message, command_name: nil, context: nil)
              super(message)
              @command_name = command_name
              @context = context
            end
          end

          class ValidationError < CommandError; end
          class ExecutionError < CommandError; end

          attr_reader :name, :description

          def initialize(name: nil, description: nil, logger: nil)
            @name = name || self.class.name.split('::').last
            @description = description || @name
            @logger = logger
          end

          # Execute command with full error handling and validation
          #
          # @param context [Object] Execution context (controller, service, etc.)
          # @param params [Hash] Command parameters
          # @return [Symbol] :handled, :pass, or :error
          def execute(context, params = {})
            normalized_params = normalize_params(params)
            validate_context(context)
            validate_parameters(normalized_params)

            return :pass unless can_execute?(context, normalized_params)

            begin
              result = perform(context, normalized_params)
              handle_success(context, result)
              :handled
            rescue StandardError => e
              handle_error(context, e, normalized_params)
              :error
            end
          end

          # Check if command can be executed
          #
          # @param context [Object] Execution context
          # @param params [Hash] Command parameters
          # @return [Boolean]
          def can_execute?(_context, _params = {})
            true # Override in subclasses for conditional execution
          end

          # Validate execution context
          #
          # @param context [Object] Execution context
          # @raise [ValidationError] if context is invalid
          def validate_context(context)
            raise ValidationError.new('Context cannot be nil', command_name: name) if context.nil?
          end

          # Validate command parameters
          #
          # @param params [Hash] Command parameters
          # @raise [ValidationError] if parameters are invalid
          def validate_parameters(params)
            # Override in subclasses for parameter validation
          end

          protected

          # Perform the actual command logic
          # Must be implemented by subclasses
          #
          # @param context [Object] Execution context
          # @param params [Hash] Command parameters
          # @return [Object] Command result
          def perform(context, params = {})
            raise NotImplementedError, "#{self.class.name} must implement #perform"
          end

          # Handle successful command execution
          #
          # @param context [Object] Execution context
          # @param result [Object] Command result
          def handle_success(context, result)
            log_success(context, result)
          end

          # Handle command execution errors
          #
          # @param context [Object] Execution context
          # @param error [StandardError] The error that occurred
          # @param params [Hash] Command parameters
          def handle_error(context, error, params = {})
            log_error(context, error, params)
          end

          private

          def log_success(context, result)
            logger = resolve_logger(context)
            logger&.debug(
              'Command executed successfully',
              command: name,
              context: context.class.name,
              result: result.inspect
            )
          end

          def log_error(context, error, params)
            logger = resolve_logger(context)
            logger&.error(
              'Command execution failed',
              command: name,
              context: context.class.name,
              error: error.message,
              params: params,
              backtrace: error.backtrace.first(5)
            )
          end

          def resolve_logger(context)
            return @logger if defined?(@logger) && @logger

            candidate = context.logger
          rescue NoMethodError
            nil
          else
            @logger = candidate if candidate
            candidate
          end

          def normalize_params(value)
            payload = InputCommandPayload.from(value)
            payload.to_h.merge(payload.metadata)
          rescue ArgumentError => e
            raise ValidationError.new(e.message, command_name: name)
          end
        end
      end
    end
  end
end
