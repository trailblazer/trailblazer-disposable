require "test_helper"

require "trailblazer-activity"

require "disposable/merge"

class ActivityTest < Minitest::Spec
  Merge = Disposable::Merge

  module Scalar
    extend Trailblazer::Activity::Railway()
    module_function

    def run_populator(ctx, **)
      true
    end

    def recurse_scalar(ctx, value:, **)
      value
      true
    end

    step method(:recurse_scalar), id: :recurse_scalar
    # step method(:run_populator)

    # definitions.collect
    module Nested
      extend Trailblazer::Activity::Railway()
      module_function

      def recurse_nested(ctx, value:, dfn:, **)
        values = dfn[:definitions].collect do |__dfn| # TODO: that should be done via TRB's loop

          binding = __dfn[:binding] # Scalar::RunBinding[::Nested]

          # Technically, we're creating a new Context here!
          signal, (_ctx, flow) = binding.( [{document: value, dfn: __dfn}] )


          # run_binding(dfn, source, **args)

          # collect :value
          _ctx[:value]
        end

        puts "@@@@@ #{values.inspect}"

        ctx[:value] = values
      end

      merge!(Scalar)
      step method(:recurse_nested), replace: :recurse_scalar
      # run_recursion
    end

    module RunBinding # only for one item
      extend Trailblazer::Activity::Railway()
      module_function

      def read(ctx, document:, dfn:, **)
        return false unless document.key?(dfn[:name])

        ctx[:value] = document[ dfn[:name] ]
      end

      def write(ctx, value:, dfn:, **)
        ctx[:value] = [dfn[:name], value]
      end

      step method(:read)
      step Subprocess(Scalar), id: :run_scalar
      step method(:write)

      module Nested
        extend Trailblazer::Activity::Railway()
        module_function

        merge!(RunBinding)

        step Subprocess(Scalar::Nested), replace: :run_scalar
      end
    end
  end

  it do
    document = {
      id: 1,
      uuid: "0x11",
      # uuid: nil,
      amount: {
        total: 9.99,
      },

      rubbish: false,
    }

    definitions = {
      name:         :_top_,

      definitions:  [
        { name: :id,     binding: Scalar::RunBinding },
        { name: :uuid,   binding: Scalar::RunBinding },
        { name: :role,   binding: Scalar::RunBinding },
        { name: :amount, binding: Scalar::RunBinding::Nested, definitions:
          [
            { name: :total,   binding: Scalar::RunBinding },
            { name: :currency, binding: Scalar::RunBinding },
          ]
        }
      ]
    }


    pp Scalar::RunBinding.( [document: document, dfn: definitions[:definitions][0]] )

    signal, (ctx, _) = Scalar::RunBinding::Nested.( [document: {_top_: document}, dfn: definitions] )

    pp signal, ctx

    ctx[:value].must_equal([:_top_, [[:id, 1], [:uuid, "0x11"], nil, [:amount, [[:total, 9.99], nil]]]])
  end





end
