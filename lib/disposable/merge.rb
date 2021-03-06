module Disposable
  module Merge
    module Build
      # DSLs always happen within blocks.
      # This DSL block must be "translated" and then executed in some target context.

      module Translator
        module_function

        # "create"
        def translate_block(options, &block)
          activity = Module.new do
            extend Trailblazer::Activity::Railway(name: name)
            extend Merge::Property::Step
          end
        end

        def for_block(nested_activity, context, name, **options)
          containered_activity = MergeTest::Container(nested_activity)

          nested_flow = Module.new do
            extend Trailblazer::Activity::Railway()
            module_function

            # we want the same mechanics here for reading from a and b, if/else, etc.
            # different to scalar: after successfully reading, we go into {process_nested}.
            # this "container" adds a private/local {merged_a}
            merge!(Merge::Property::Nested)

            step Subprocess(containered_activity), replace: :process_nested,Output(:failure) => Track(:success) # FIXME: why?
          end

          translate(name, context: context, subprocess: nested_flow)
        end

        def for_scalar(context, name, scalar: Merge::Property::Scalar.clone, &block)
          translate(name, {context: context, subprocess: scalar})
        end

        def translate(name, context:, subprocess:)
          context.step context.Subprocess(subprocess),
            input:  Merge::Property.input(name),
            output: Merge::Property.output(name),
          context.Output(:failure)=>context.Track(:success) # FIXME: why?
        end
      end

      class DSL
        def initialize(target_context:, translator:)
          @context    = target_context
          @translator = translator
        end

        def property(*args, &block)
          if block_given?

            nested_activity = Build.for_block(@translator, *args, &block)

            @translator.for_block(nested_activity, @context, *args, &block)
          else
            puts "@@@@@ #{args.inspect}"
            @translator.for_scalar(@context, *args, &block)
          end
        end

        def call(&block)
          instance_exec(&block)

          @context
        end
      end
      module_function


      # def for_block(*args, &block)
      def for_block(translator, *args, &block)
        # concrete
        # build the target
        block_target = translator.translate_block(*args, &block)

        # generic
        # execute the DSL block and translate its instructions to the target
        dsl = DSL.new(target_context: block_target, translator: translator)
        dsl.(&block)
      end
    end


    module Property
      module_function

      def input(name)
        ->(ctx, **) {
          puts "@@@@@ #{ctx.object_id} #{name.upcase}/in  "
          _ctx = Trailblazer::Context(ctx, dfn: {name: name})
          puts "@@@@@ #{_ctx.object_id} #{name.upcase}/in/ "
          _ctx
        }
      end

      def output(name)
        ->(original, ctx, **) {
          puts "@@@@@ #{ctx.object_id} #{name.upcase}/out  "

          outer, inner = ctx.decompose

          puts "@@@@@ #{outer.object_id} #{name.upcase}/out/ "

          outer[:merged_a] = inner[:merged_a] # DISCUSS: can we do this by "not" mutating?
          outer
        }
      end

# FIXME: change normalizer instead
module Step
      def step(task, options)
        options = options.dup
        input, output = options.delete(:input), options.delete(:output)

        if input
          options = options.merge(Trailblazer::Activity::TaskWrap::VariableMapping.extension_for(

            Trailblazer::Activity::TaskWrap::Input.new(input),
            Trailblazer::Activity::TaskWrap::Output.new(output)) => true)
        end

        super(task, options)
      end
    end


      module Scalar
        extend Trailblazer::Activity::Railway()
        module_function

        def read_a_field(ctx, a:, dfn:, **) # TODO: merge with Scalar::read
          puts "reading a #{dfn[:name]} #{a.inspect}"
          return false unless a.key?(dfn[:name])

          ctx[:value] = a[ dfn[:name] ]
        end

        def read_b_field(ctx, b:, dfn:, **) # TODO: merge with Scalar::read
          puts "-- reading #{b} #{dfn}"
          return false unless b.key?(dfn[:name])

          ctx[:value] = b[ dfn[:name] ]
        end

        def merge_value_into_a(ctx, merged_a:, dfn:, value:, **)
          ctx[:merged_a] = merged_a.merge(dfn[:name] => value)
        end

        step method(:read_a_field), id: :read_a_field
        fail method(:read_b_field).clone,
          id: :read_b_field_1,
          Output(:success) => "write_b",
          Output(:failure) => "End.failure"

          step method(:merge_value_into_a), magnetic_to: [], id: "write_b", Output(:success)=>"End.success", Output(:failure)=>"End.failure"

        step method(:read_b_field), id: :read_b_field_2
        fail method(:merge_value_into_a).clone, id: :write_a # if no b, we want a
        step method(:merge_value_into_a).clone, id: :overwrite_a_with_b
      end

      # pp Scalar.to_h[:circuit]
      # raise

      module Nested
        extend Trailblazer::Activity::Railway()
        module_function

        extend Scalar

        extend Step

        merge!(Scalar)

        step method(:read_a_field).clone, replace: :read_a_field,
          input:  ->(ctx, **) {
            puts "&&& 2 Container #{ctx.object_id}"
            ctx },
          output: ->(original, ctx, **) { ctx[:a] = ctx[:value]; ctx }

        # step method(:read_b_field).clone, replace: :read_b_field_1, input: ->(ctx, **) { ctx }, output: ->(ctx, value:, **) { ctx.merge(b: value) }
        step method(:read_b_field).clone, replace: :read_b_field_2,
          input:  ->(ctx, **) { ctx },
          output: ->(original, ctx, **) { ctx[:b] = ctx[:value]; ctx }, id: :read_b_field_2

        step :nil, after: :read_b_field_2, id: :process_nested, # nest
          Output(:failure) => Track(:success) # FIXME: why?
      end
    end
  end
end
