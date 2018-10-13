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


    # this "container" adds a private/local {:merged_a} and writes it to {:value} after.
    def self.Container(activity)
      Module.new do
        extend Trailblazer::Activity::Railway()
        module_function

        extend Merge::Property::Step

        step Subprocess(activity),
          input: ->(ctx, **) {
            new_ctx = Trailblazer::Context(ctx, merged_a: {})
            puts "&&& /1 Container #{new_ctx.object_id}"
            new_ctx
          },
          output: ->(original, ctx, **) {
            puts "&&& \\1 Container #{ctx.object_id}"
            original, _ctx = ctx.decompose

            original[:value] = _ctx[:merged_a]
            original
          }
      end
    end

    module Expense
      extend Trailblazer::Activity::Railway()
      module_function



      module Amount
        extend Trailblazer::Activity::Railway()
        module_function

        extend Merge::Property::Step

        step Subprocess(Merge::Property::Scalar),
          input:  Merge::Property.input(:total),
          output: Merge::Property.output(:total),
          Output(:failure) => Track(:success)
        step Subprocess(Merge::Property::Scalar.clone),
          input:  Merge::Property.input(:currency),
          output: Merge::Property.output(:currency)
      end


      ContaineredAmount = ActivityTest::Container(Amount)

      module NestedAmount # @isa Merge::Property::Nested -> Merge::Property::Scalar
        extend Trailblazer::Activity::Railway()
        module_function

        # we want the same mechanics here for reading from a and b, if/else, etc.
        # different to scalar: after successfully reading, we go into {process_nested}.
        # this "container" adds a private/local {merged_a}
        merge!(Merge::Property::Nested)

        step Subprocess(ContaineredAmount), replace: :process_nested,Output(:failure) => Track(:success) # FIXME: why?
      end

      extend Merge::Property::Step

      # step method(:inject_merged_a)
      # step Subprocess(Merge::Property::Scalar),
      step Subprocess(Merge::Property::Scalar.clone),
        input:  Merge::Property.input(:id),
        output: Merge::Property.output(:id)

      step Subprocess(Merge::Property::Scalar.clone),
        input:  Merge::Property.input(:uuid),
        output: Merge::Property.output(:uuid),
        Output(:failure)=>Track(:success) # FIXME: why?

      step Subprocess(NestedAmount),
        input:  Merge::Property.input(:amount),
        output: Merge::Property.output(:amount) # FIXME: should be AMOUNT
    end

    def invoke(activity, a, b, **options)
      # ctx = Trailblazer::Context({a: a, b: b}.merge(options))
      ctx = Trailblazer::Context({a: a, b: b})

      ctx = Trailblazer::Context(ctx, options) if options.any?

      old_ctx = ctx

       stack, signal, (ctx, _) = Trailblazer::Activity::Trace.invoke(activity, [ctx, {}])

       output = Trailblazer::Activity::Trace::Present.(stack)
       puts output

       return ctx, old_ctx, signal
    end

  it "controlled deep merge" do
    a = {
      id: 1,
      uuid: "0x11",
      # uuid: nil,
      amount: {
        total: 9.99,
        currency: :USD, # TODO: remove one field here and have it in b.
      }.freeze,

      rubbish: false,
    }.freeze

    b = {
      id: 2,          # changed, but unsolicited (read-only)
      role:   :admin, # new field
      amount: {
        currency: :EUR,
        total: 99.9,
        bogus: true,
      }.freeze
    }.freeze

    # a is the base, b gets merged into a
    # but only a few fields, with "conditions"
    # if no a or b field present, skip

    definition = { name: :id,
      #binding: Scalar::RunBinding
    }

    expense = ActivityTest::Container(Expense)


    ctx, old_ctx = invoke(expense, a, b)
    # pp signal, ctx
    ctx[:value].must_equal({:id=>2, :uuid=>"0x11", :amount=>{:total=>99.9, :currency=>:EUR}})
    ctx.object_id.must_equal old_ctx.object_id

    # {total} missing in {b}
    ctx, old_ctx = invoke(expense, a, {
      id: 2,          # changed, but unsolicited (read-only)
      role:   :admin, # new field
      amount: {
        currency: :EUR,
        # total: 99.9,
      }.freeze
    }.freeze)

    # pp signal, ctx
    ctx[:value].must_equal({:id=>2, :uuid=>"0x11", :amount=>{:total=>9.99, :currency=>:EUR}})

  end

  it Merge::Property::Nested do
    a = {
      amount: {
        total: 9.99,
        currency: :USD,
      }.freeze,

      rubbish: false,
    }.freeze

    b = {
      amount: {
        currency: :EUR,
        total: 99.9,
        bogus: true,
      }.freeze
    }.freeze

    ctx, old_ctx, signal = invoke(Expense::NestedAmount, a, b, dfn: {name: :amount}, merged_a: {})
    ctx[:value].must_equal({:total=>99.9, :currency=>:EUR})
    signal.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:success>}


    ctx, old_ctx, signal = invoke(Expense::NestedAmount, a, {amount: {total: 99.9}}, dfn: {name: :amount}, merged_a: {})
    ctx[:value].must_equal({:total=>99.9, :currency=>:USD})
    signal.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:success>}

    ctx, old_ctx, signal = invoke(Expense::NestedAmount, {amount: {}}, {amount: {total: 99.9, currency: :EUR}}, dfn: {name: :amount}, merged_a: {})
    ctx[:value].must_equal({:total=>99.9, :currency=>:EUR})
    signal.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:success>}

    ctx, old_ctx, signal = invoke(Expense::NestedAmount,
      {amount: {currency: :USD}},
      {amount: {total: 99.9}},
      dfn: {name: :amount}, merged_a: {})
    ctx[:value].must_equal({:total=>99.9, :currency=>:USD})
    signal.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:success>}

puts "+++++++++"
    ctx, old_ctx, signal = invoke(Expense::NestedAmount,
      {amount: {currency: :USD, total: 9.9}},
      {amount: {currency: :EUR}},
      dfn: {name: :amount}, merged_a: {})
    signal.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:success>}
    ctx[:value].must_equal({:total=>9.9, :currency=>:EUR})
  end

  it Merge::Property::Scalar do
    definition = { name: :id,
      #binding: Scalar::RunBinding
    }

    a = {
      id: 1,
      uuid: "0x11",
      # uuid: nil,
      amount: {
        total: 9.99,
        currency: :USD, # TODO: remove one field here and have it in b.
      }.freeze,

      rubbish: false,
    }.freeze

    b = {
      id: 2,          # changed, but unsolicited (read-only)
      role:   :admin, # new field
      amount: {
        currency: :EUR,
        total: 99.9,
        bogus: true,
      }.freeze
    }.freeze

    signal, (ctx, _) = Merge::Property::Scalar.( [a: a, b: {}, merged_a: {}, dfn: definition] )
    ctx[:merged_a].must_equal({:id=>1})

    signal, (ctx, _) = Merge::Property::Scalar.( [a: {}, b: {}, merged_a: {}, dfn: definition] )
    ctx[:merged_a].must_equal({})

    signal, (ctx, _) = Merge::Property::Scalar.( [a: {}, b: {id:3}, merged_a: {}, dfn: definition] )
    ctx[:merged_a].must_equal({:id=>3})


    # test
    # a-amount-{total}
    # b-amount-{currency}
    # nur b-amount
    # b-amount in a reinmergen

  end
end
