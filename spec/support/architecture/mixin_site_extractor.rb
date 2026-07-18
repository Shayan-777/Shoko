# frozen_string_literal: true

require 'ripper'

module SpecSupport
  module Architecture
    # AST-backed extraction of module/class definitions and mixin sites
    # (`include`/`prepend`/`extend`) from a Ruby source. Ripper parses the
    # real grammar, so multi-argument (`include A, B`), parenthesized,
    # multiline, and `::`-anchored spellings are all seen exactly as Ruby
    # sees them — line regexes cannot promise that.
    module MixinSiteExtractor
      MIXIN_METHODS = %w[include prepend extend].freeze

      # A single mixin site: the method used, the constant path as written
      # (without a leading ::), whether it was top-level anchored (::Const),
      # and the lexical module/class nesting it appeared under.
      Site = Struct.new(:method, :const, :top_level, :nesting, keyword_init: true)

      # A definition: the fully-qualified name segments and nesting depth.
      Definition = Struct.new(:segments, :depth, keyword_init: true)

      module_function

      # @return [Array(Array<Definition>, Array<Site>)] or [[], []] for
      #   unparseable source.
      def extract(source)
        sexp = Ripper.sexp(source)
        return [[], []] unless sexp

        defs = []
        sites = []
        walk(sexp, [], defs, sites)
        [defs, sites]
      end

      def walk(node, stack, defs, sites)
        return unless node.is_a?(Array)

        case node.first
        when :module then walk_module(node, stack, defs, sites)
        when :class then walk_class(node, stack, defs, sites)
        when :command then collect_command(node, stack, sites)
        when :method_add_arg then collect_paren_call(node, stack, sites)
        end

        node.each { |child| walk(child, stack, defs, sites) if skippable_walk?(node, child) }
      end

      # module/class nodes are walked explicitly (with the pushed stack), so
      # the generic child walk must not descend into them again.
      def skippable_walk?(node, child)
        !%i[module class].include?(node.first) && child.is_a?(Array)
      end

      def walk_module(node, stack, defs, sites)
        name = const_segments(node[1])
        record_definition(defs, stack, name)
        walk(node[2], stack + name, defs, sites)
      end

      def walk_class(node, stack, defs, sites)
        name = const_segments(node[1])
        record_definition(defs, stack, name)
        walk(node[2], stack, defs, sites) if node[2] # superclass expression stays in outer nesting
        walk(node[3], stack + name, defs, sites)
      end

      def record_definition(defs, stack, name)
        return if name.empty?

        defs << Definition.new(segments: stack + name, depth: stack.length)
      end

      # `include Foo, Bar` — a :command node.
      def collect_command(node, stack, sites)
        method = ident_name(node[1])
        return unless MIXIN_METHODS.include?(method)

        collect_argument_consts(node[2], method, stack, sites)
      end

      # `include(Foo)` — an :fcall wrapped in :method_add_arg / :arg_paren.
      def collect_paren_call(node, stack, sites)
        fcall = node[1]
        return unless fcall.is_a?(Array) && fcall.first == :fcall

        method = ident_name(fcall[1])
        return unless MIXIN_METHODS.include?(method)

        args = node[2]
        args = args[1] if args.is_a?(Array) && args.first == :arg_paren
        collect_argument_consts(args, method, stack, sites)
      end

      def collect_argument_consts(args_node, method, stack, sites)
        each_argument(args_node) do |arg|
          const, top_level = const_path(arg)
          next unless const

          sites << Site.new(method: method, const: const, top_level: top_level, nesting: stack.dup)
        end
      end

      def each_argument(args_node, &)
        return unless args_node.is_a?(Array)

        list = args_node.first == :args_add_block ? args_node[1] : args_node
        return unless list.is_a?(Array)

        list.each(&)
      end

      # @return [Array(String, Boolean), nil] const path and top-level flag,
      #   or nil for non-constant arguments.
      def const_path(node)
        return nil unless node.is_a?(Array)

        case node.first
        when :var_ref, :const_ref
          name = const_leaf(node[1])
          name && [name, false]
        when :top_const_ref
          name = const_leaf(node[1])
          name && [name, true]
        when :const_path_ref
          base = const_path(node[1])
          leaf = const_leaf(node[2])
          base && leaf ? ["#{base[0]}::#{leaf}", base[1]] : nil
        end
      end

      def const_segments(node)
        path = const_path(node)
        path ? path[0].split('::') : []
      end

      def const_leaf(node)
        node.is_a?(Array) && node.first == :@const ? node[1] : nil
      end

      def ident_name(node)
        node.is_a?(Array) && node.first == :@ident ? node[1] : nil
      end
    end
  end
end
