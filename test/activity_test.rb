require "test_helper"

require "trailblazer-activity"

class ActivityTest < Minitest::Spec
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
    step method(:run_populator)

    module Nested
      extend Trailblazer::Activity::Railway()
      module_function

      def recurse_nested(ctx, value:, dfn:, **)
        raise (dfn[:definitions].collect do |__dfn| # TODO: that should be done via TRB's loop
                  signal, ctx = Scalar::RunBinding.( [document: value, dfn: __dfn] )
                  # run_binding(dfn, source, **args)
                  ctx
                end).inspect
        # collect :value
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

  document = {
    id: 1,
    uuid: "0x11",
    # uuid: nil,
  }

  definitions = {
    name:         :_top_,
    definitions:  [
      { name: :id },
      { name: :uuid },
    ]
  }


  pp Scalar::RunBinding.( [document: document, dfn: definitions[:definitions][0]] )

  pp Scalar::RunBinding::Nested.( [document: {_top_: document}, dfn: definitions] )
end
