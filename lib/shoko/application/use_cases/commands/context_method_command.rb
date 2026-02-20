# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Commands
        # Generic command that dispatches to a same-name method on the runtime context.
        # Used as a fallback for adapter-facing input actions.
        class ContextMethodCommand
          def initialize(method_name)
            @method_name = method_name.to_sym
          end

          def execute(context, params = {})
            return :pass unless context
            return :pass unless context.respond_to?(@method_name)

            result = invoke_context_method(context, params)
            result.nil? ? :handled : result
          rescue StandardError
            :pass
          end

          private

          def invoke_context_method(context, params)
            explicit_args = Array(params[:args])
            return context.public_send(@method_name, *explicit_args) unless explicit_args.empty?

            key = params[:key]
            method_arity = context.method(@method_name).arity

            if method_arity.zero?
              context.public_send(@method_name)
            elsif params.key?(:key)
              context.public_send(@method_name, key)
            else
              context.public_send(@method_name)
            end
          rescue ArgumentError
            context.public_send(@method_name)
          end
        end
      end
    end
  end
end
