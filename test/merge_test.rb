require "test_helper"
require "trailblazer-activity"

require "disposable/merge"

class MergeTest < Minitest::Spec
  Merge = Disposable::Merge

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


      ContaineredAmount = MergeTest::Container(Amount)

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


       renderer = ->(level:, input:, name:, **) {
        ctx = input.data.first

        data = {}
        # puts "@@@@@ #{ctx[:merged_a].inspect}"
        data = input.data[1] if ctx[:dfn] && (ctx[:dfn][:name] == :h || ctx[:dfn][:name] == :g)

        [level, %{#{ctx[:dfn]} % #{name} / #{data}}]

      }

       output = Trailblazer::Activity::Trace::Present.(stack, renderer: renderer)
       puts output

       return ctx, old_ctx, signal
    end

  describe "#what" do
    let(:a) {
      a = {
        a: 1,
        b: 2,
        c: {
          d: 3,
          e: 4,
          f: {
            g: 5,
            h: 6,
            bull: "shit",
          }
        },
        rubbish: true,
      }
    }

    let(:b) {
      b = {
        a: 9,
        c: {
          d: 10,
          f: {
            g: 11,
            ignore: "this",
          }
        }
      }
    }

    it "does a beautiful deep merge" do
      merge = Disposable::Merge::Build.for_block(name: :top) do
        #merge
        property :a
        property :b
        property :c do
          #merge (merge all b (d,e,f) into a)
          property :d
          property :e
          property :f do
            property :g
            property :h
          end
        end
      end

      ctx, old_ctx = invoke(merge, a, b, merged_a: {})
      # pp signal, ctx
      ctx[:merged_a].must_equal({
        :a=>9, :b=>2, :c=>{:d=>10, :e=>4, :f=>{:g=>11, :h=>6}}
      })
    end

    it "does a beautiful planned merge" do
      module Planned
        module Scalar
          extend Trailblazer::Activity::Railway()
          module_function

          merge!(Disposable::Merge::Property::Scalar)

          # delete all a-related steps as we only want b.
          step nil, delete: :read_a_field
          step nil, delete: :read_b_field_1
          step nil, delete: "write_b"
          extend Disposable::Merge::Property::Step
          fail Disposable::Merge::Property::Scalar.method(:merge_value_into_a), replace: :write_a,
            input: ->(ctx, **) { ctx[:value] = nil; ctx },
            output: ->(ctx, **) { ctx }
        end

        # pp Scalar.to_h[:circuit]
      end

      merge = Disposable::Merge::Build.for_block(name: :top) do
        #merge
        property :a
        property :b
        property :c do
          #merge (merge all b (d,e,f) into a)
          property :d
          property :e

          # current implementation:
          # 1. merged_a: {}
          # 2. merged_a.merge(g: from_a)
          # 3. merged_a.merge(g: from_b)

          # alternative:
          # 1. merged_a: {}
          # 2. merged_b: {}
          # 3. merged_a.merge(g: from_a)
          # 4. merged_b.merge(g: from_b)
          # 5. merged_a.merge(merged_b)

          # alternative
          #
          # 1. merged_a: {}
          # 2. merged_a.merge(g: from_b)
          # DISCUSS: what to do if no b present, only a?

          property :f do
            # b wins, a.f will always be overridden by b.f if exists
            property :g, scalar: Planned::Scalar
            property :h, scalar: Planned::Scalar#,  merge: :skip_a
          end
        end
      end

      ctx, old_ctx = invoke(merge, a, b, merged_a: {})
      # pp signal, ctx
      ctx[:merged_a].must_equal({
        :a=>9, :b=>2, :c=>{:d=>10, :e=>4, :f=>{:g=>11, h: nil}}
      })

    end
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

    expense = MergeTest::Container(Expense)


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
