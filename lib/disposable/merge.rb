module Disposable
  module Merge
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
        # puts "@@@@@ #{original.object_id}... #{mutated.object_id} ??? #{original.inspect}"
        # o=original.merge(merged_a: mutated[:merged_a])
          puts "@@@@@ #{outer.object_id} #{name.upcase}/out/ "

          puts inner.inspect

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
          Output(:success) => :write_b,
          Output(:failure) => "End.failure"

          step method(:merge_value_into_a), magnetic_to: [], id: :write_b, Output(:success)=>"End.success", Output(:failure)=>"End.failure"

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