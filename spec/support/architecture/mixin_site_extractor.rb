# frozen_string_literal: true

require 'ripper'

module SpecSupport
  module Architecture
    # Ripper-backed extraction of module/class definitions, constant aliases,
    # and every direct mixin invocation from Ruby source.
    module MixinSiteExtractor
      MIXIN_METHODS = %w[include prepend extend].freeze
      SEND_METHODS = %w[send public_send __send__].freeze

      Site = Struct.new(:method, :const, :top_level, :nesting, :line, keyword_init: true)
      Definition = Struct.new(:segments, :depth, keyword_init: true)
      ConstantAlias = Struct.new(
        :name, :name_top_level, :target, :target_top_level, :nesting, keyword_init: true
      )
      DynamicSite = Struct.new(:method, :nesting, :line, keyword_init: true)

      module_function

      # @return [definitions, sites, aliases, dynamic_sites]. Unparseable
      # source returns four empty arrays; the normal test/load path reports the
      # syntax error independently.
      def extract(source)
        sexp = Ripper.sexp(source)
        return [[], [], [], []] unless sexp

        collections = { definitions: [], sites: [], aliases: [], dynamic_sites: [] }
        walk(sexp, [], collections)
        collections.values_at(:definitions, :sites, :aliases, :dynamic_sites)
      end

      def walk(node, stack, collections)
        return unless node.is_a?(Array)

        unless ast_node?(node)
          node.each { |child| walk(child, stack, collections) if child.is_a?(Array) }
          return
        end

        case node.first
        when :module then walk_module(node, stack, collections)
        when :class then walk_class(node, stack, collections)
        when :assign then collect_alias(node, stack, collections[:aliases])
        when :command then collect_command(node, stack, collections)
        when :command_call then collect_command_call(node, stack, collections)
        when :method_add_arg then collect_paren_call(node, stack, collections)
        end

        return if %i[module class].include?(node.first)

        node.each { |child| walk(child, stack, collections) if child.is_a?(Array) }
      end

      def walk_module(node, stack, collections)
        name = const_segments(node[1])
        record_definition(collections[:definitions], stack, name)
        walk(node[2], stack + name, collections)
      end

      def walk_class(node, stack, collections)
        name = const_segments(node[1])
        record_definition(collections[:definitions], stack, name)
        walk(node[3], stack + name, collections)
      end

      def record_definition(definitions, stack, name)
        return if name.empty?

        definitions << Definition.new(segments: stack + name, depth: stack.length)
      end

      def collect_alias(node, stack, aliases)
        name = const_path(node[1])
        target = const_path(node[2])
        return unless name && target

        aliases << ConstantAlias.new(
          name: name[0], name_top_level: name[1],
          target: target[0], target_top_level: target[1], nesting: stack.dup
        )
      end

      def collect_command(node, stack, collections)
        method = ident_name(node[1])
        if MIXIN_METHODS.include?(method)
          collect_argument_consts(node[2], method, stack, collections)
        elsif SEND_METHODS.include?(method)
          collect_send(node[2], stack, collections)
        end
      end

      def collect_command_call(node, stack, collections)
        method = ident_name(node[3])
        if MIXIN_METHODS.include?(method)
          collect_explicit_mixin(node[1], node[4], method, stack, collections)
        elsif SEND_METHODS.include?(method)
          collect_send(node[4], stack, collections)
        end
      end

      def collect_paren_call(node, stack, collections)
        call = node[1]
        method = call_method_name(call)
        return unless method

        args = unwrap_arg_paren(node[2])
        if MIXIN_METHODS.include?(method)
          if call.first == :fcall
            collect_argument_consts(args, method, stack, collections)
          else
            collect_explicit_mixin(call[1], args, method, stack, collections)
          end
        elsif SEND_METHODS.include?(method)
          collect_send(args, stack, collections)
        end
      end

      # An explicit receiver may be an ordinary object with a same-named
      # method (String#prepend is the common case). It is a statically visible
      # mixin invocation when the receiver is a module-shaped constant/self,
      # or when at least one target argument is itself a constant.
      def collect_explicit_mixin(receiver, args_node, method, stack, collections)
        arguments, dynamic = expand_arguments(args_node)
        has_constant = arguments.any? { |argument| const_path(argument) }
        return unless module_receiver?(receiver) || has_constant

        collect_expanded_arguments(arguments, dynamic, method, stack, collections)
      end

      def collect_send(args_node, stack, collections)
        arguments, dynamic = expand_arguments(args_node)
        method = symbol_name(arguments.shift)
        return unless MIXIN_METHODS.include?(method)

        collect_expanded_arguments(arguments, dynamic, method, stack, collections)
      end

      def collect_argument_consts(args_node, method, stack, collections)
        arguments, dynamic = expand_arguments(args_node)
        collect_expanded_arguments(arguments, dynamic, method, stack, collections)
      end

      def collect_expanded_arguments(arguments, dynamic_splat, method, stack, collections)
        arguments.each do |argument|
          const, top_level = const_path(argument)
          if const
            collections[:sites] << Site.new(
              method: method, const: const, top_level: top_level,
              nesting: stack.dup, line: source_line(argument)
            )
          elsif !(method == 'extend' && self_argument?(argument))
            collections[:dynamic_sites] << DynamicSite.new(
              method: method, nesting: stack.dup, line: source_line(argument)
            )
          end
        end
        return unless dynamic_splat

        collections[:dynamic_sites] << DynamicSite.new(method: method, nesting: stack.dup, line: nil)
      end

      # Flatten normal argument lists and literal-array splats. A dynamic splat
      # is reported separately so architecture enforcement can reject a mixin
      # site whose target modules cannot be statically counted.
      def expand_arguments(node, acc = [])
        return [acc, false] unless node.is_a?(Array)

        if !ast_node?(node)
          dynamic = false
          node.each do |child|
            _arguments, child_dynamic = expand_arguments(child, acc)
            dynamic = true if child_dynamic
          end
          return [acc, dynamic]
        end

        case node.first
        when :args_add_block
          expand_arguments(node[1], acc)
        when :args_add_star
          _, leading_dynamic = expand_arguments(node[1], acc)
          splat = node[2]
          splat_dynamic = if ast_node?(splat) && splat.first == :array
                            expand_arguments(splat[1], acc)[1]
                          else
                            true
                          end
          trailing_dynamic = false
          node.drop(3).each do |trailing|
            _arguments, child_dynamic = expand_arguments(trailing, acc)
            trailing_dynamic = true if child_dynamic
          end
          [acc, leading_dynamic || splat_dynamic || trailing_dynamic]
        when :array
          expand_arguments(node[1], acc)
        else
          acc << node
          [acc, false]
        end
      end

      def unwrap_arg_paren(node)
        node.is_a?(Array) && node.first == :arg_paren ? node[1] : node
      end

      def call_method_name(node)
        return unless ast_node?(node)

        case node.first
        when :fcall then ident_name(node[1])
        when :call then ident_name(node[3])
        end
      end

      def const_path(node)
        return nil unless ast_node?(node)

        case node.first
        when :var_ref, :const_ref, :var_field
          name = const_leaf(node[1])
          name && [name, false]
        when :top_const_ref, :top_const_field
          name = const_leaf(node[1])
          name && [name, true]
        when :const_path_ref, :const_path_field
          base = const_path(node[1])
          leaf = const_leaf(node[2])
          base && leaf ? ["#{base[0]}::#{leaf}", base[1]] : nil
        end
      end

      def const_segments(node)
        path = const_path(node)
        path ? path[0].split('::') : []
      end

      def symbol_name(node)
        return unless ast_node?(node) && node.first == :symbol_literal

        symbol = node.dig(1, 1)
        symbol.is_a?(Array) ? symbol[1] : nil
      end

      def self_argument?(node)
        ast_node?(node) && node.first == :var_ref && node.dig(1, 0) == :@kw && node.dig(1, 1) == 'self'
      end

      def module_receiver?(node) = const_path(node) || self_argument?(node)

      def source_line(node)
        return unless node.is_a?(Array)
        return node.dig(2, 0) if node.first.to_s.start_with?('@') && node[2].is_a?(Array)

        node.each do |child|
          line = source_line(child)
          return line if line
        end
        nil
      end

      def ast_node?(node) = node.is_a?(Array) && node.first.is_a?(Symbol)

      def const_leaf(node) = ast_node?(node) && node.first == :@const ? node[1] : nil

      def ident_name(node) = ast_node?(node) && node.first == :@ident ? node[1] : nil
    end
  end
end
