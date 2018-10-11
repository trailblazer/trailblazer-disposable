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

    module Merge
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

        def write_b(ctx, merged_a:, dfn:, value:, **)
          puts "write b: #{value}"
          ctx[:merged_a] = merged_a.merge(dfn[:name] => value)
        end

        step method(:read_a_field), id: :read_a_field
        fail method(:read_b_field).clone,
          id: :read_b_field_1,
          Output(:success) => :write_b,
          Output(:failure) => "End.failure"

          step method(:write_b), magnetic_to: [], id: :write_b, Output(:success)=>"End.success", Output(:failure)=>"End.failure"

        step method(:read_b_field), id: :read_b_field_2
        fail method(:write_b).clone, id: :write_a # if no b, we want a
        step method(:write_b).clone, id: :overwrite_a_with_b
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
          input:  ->(ctx, **) { ctx },
          output: ->(original, ctx, **) { ctx[:a] = ctx[:value]; ctx }

        # step method(:read_b_field).clone, replace: :read_b_field_1, input: ->(ctx, **) { ctx }, output: ->(ctx, value:, **) { ctx.merge(b: value) }
        step method(:read_b_field).clone, replace: :read_b_field_2,
          input:  ->(ctx, **) { ctx },
          output: ->(original, ctx, **) { ctx[:b] = ctx[:value]; ctx }, id: :read_b_field_2

        step :nil, after: :read_b_field_2, id: :process_nested, # nest
          Output(:failure) => Track(:success) # FIXME: why?
        # step ->(ctx, **) { raise ctx.inspect }, after: :process_nested # nest

      end
    end

    pp Scalar.to_h[:circuit]


    # this "container" adds a private/local {:merged_a} and writes it to {:value} after.
    def self.Container(activity)
      Module.new do
        extend Trailblazer::Activity::Railway()
        module_function

        extend Step

        step Subprocess(activity),
          input: ->(ctx, **) {
            new_ctx = Trailblazer::Context(ctx, merged_a: {})
            new_ctx
          },
          output: ->(original, ctx, **) {
            original, _ctx = ctx.decompose

            original[:value] = _ctx[:merged_a]
            original
          }
      end
    end

    module Expense
      extend Trailblazer::Activity::Railway()
      module_function

      def input(name)
        ->(ctx, **) {
          puts "@@@@@ #{ctx.object_id} #{name.upcase}/in  "
          _ctx = Trailblazer::Context(ctx, dfn: {name: name}) # DISCUSS: this mixes the "new local state" with the old state in {mutable}
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

      module Amount
        extend Trailblazer::Activity::Railway()
        module_function

        extend Step

        step Subprocess(Merge::Scalar),
          input:  Expense.input(:total),
          output: Expense.output(:total)
        step Subprocess(Merge::Scalar.clone),
          input:  Expense.input(:currency),
          output: Expense.output(:currency)
      end


      NestedAmount2 = ActivityTest::Container(Amount)

      module NestedAmount
        extend Trailblazer::Activity::Railway()
        module_function

        # we want the same mechanics here for reading from a and b, if/else, etc.
        # different to scalar: after successfully reading, we go into {process_nested}.
        # this "container" adds a private/local {merged_a}
        merge!(Merge::Nested)

        step Subprocess(NestedAmount2), replace: :process_nested,Output(:failure) => Track(:success) # FIXME: why?

      end

      extend Step

      # step method(:inject_merged_a)
      # step Subprocess(Merge::Scalar),
      step Subprocess(Merge::Scalar.clone),
        input:  Expense.input(:id),
        output: Expense.output(:id)

      step Subprocess(Merge::Scalar.clone),
        input:  Expense.input(:uuid),
        output: Expense.output(:uuid),
        Output(:failure)=>Track(:success) # FIXME: why?

      step Subprocess(NestedAmount),
        input:  Expense.input(:amount),
        output: Expense.output(:amount) # FIXME: should be AMOUNT
    end

    def invoke(activity, a, b, **options)
      # ctx = Trailblazer::Context({a: a, b: b}.merge(options))
      ctx = Trailblazer::Context({a: a, b: b})

      ctx = Trailblazer::Context(ctx, options) if options.any?

      old_ctx = ctx

       signal, (ctx, _) = Trailblazer::Activity::TaskWrap.invoke(activity, [ctx])

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

  it Merge::Nested do
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
    ctx[:value].must_equal({:total=>99.9, :currency=>:USD})
  end

  it Merge::Scalar do
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

    signal, (ctx, _) = Merge::Scalar.( [a: a, b: {}, merged_a: {}, dfn: definition] )
    ctx[:merged_a].must_equal({:id=>1})

    signal, (ctx, _) = Merge::Scalar.( [a: {}, b: {}, merged_a: {}, dfn: definition] )
    ctx[:merged_a].must_equal({})

    signal, (ctx, _) = Merge::Scalar.( [a: {}, b: {id:3}, merged_a: {}, dfn: definition] )
    ctx[:merged_a].must_equal({:id=>3})


    # test
    # a-amount-{total}
    # b-amount-{currency}
    # nur b-amount
    # b-amount in a reinmergen

  end
end
