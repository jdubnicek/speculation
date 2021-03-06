# frozen_string_literal: true

# This is a Ruby translation of clojure.spec:
#   https://github.com/clojure/clojure/blob/master/src/clj/clojure/spec.clj
# All credit belongs with Rich Hickey and contributors for their original work.

module Speculation
  # @private
  class FSpec < Spec
    include NamespacedSymbols
    S = Speculation

    attr_reader :args, :ret, :fn, :block

    def initialize(args: nil, ret: nil, fn: nil, block: nil, gen: nil)
      @args  = args
      @ret   = ret || :"Speculation/any"
      @fn    = fn
      @block = block
      @gen   = gen
    end

    def conform(f)
      raise "Can't conform fspec without args spec: #{inspect}" unless @args

      return :"Speculation/invalid" unless f.respond_to?(:call)

      specs = { :args => @args, :ret => @ret, :fn => @fn, :block => @block }

      if f.equal?(FSpec.validate_fn(f, specs, S.fspec_iterations))
        f
      else
        :"Speculation/invalid"
      end
    end

    def unform(f)
      f
    end

    def explain(path, via, inn, f)
      unless f.respond_to?(:call)
        return [{ :path => path, :pred => [f.method(:respond_to?), [:call]], :val => f, :via => via, :in => inn }]
      end

      specs = { :args => @args, :ret => @ret, :fn => @fn, :block => @block }
      validate_fn_result = FSpec.validate_fn(f, specs, 100)
      return if f.equal?(validate_fn_result)

      ret = f.call(*validate_fn_result[:args], &validate_fn_result[:block]) rescue $!

      if ret.is_a?(Exception)
        # no args available for pred
        pred = [f, validate_fn_result[:args]]
        pred << validate_fn_result[:block] if validate_fn_result[:block]
        return [{ :path => path, :pred => pred, :val => validate_fn_result, :reason => ret.message.chomp, :via => via, :in => inn }]
      end

      cret = S.dt(@ret, ret)
      return S.explain1(@ret, Utils.conj(path, :ret), via, inn, ret) if S.invalid?(cret)

      if @fn
        cargs = S.conform(@args, args)
        S.explain1(@fn, Utils.conj(path, :fn), via, inn, :args => cargs, :ret => cret)
      end
    end

    def with_gen(gen)
      self.class.new(:args => @args, :ret => @ret, :fn => @fn, :block => @block, :gen => gen)
    end

    def gen(overrides, _path, _rmap)
      return @gen.call if @gen

      ->(_rantly) do
        ->(*args, &block) do
          unless S.pvalid?(@args, args)
            raise S.explain_str(@args, args)
          end

          if @block && !S.pvalid?(@block, block)
            raise S.explain_str(@block, block)
          end

          S::Gen.generate(S.gen(@ret, overrides))
        end
      end
    end

    # @private
    # returns f if valid, else smallest
    def self.validate_fn(f, specs, iterations)
      args_gen      = S.gen(specs[:args])
      block_gen     = specs[:block] ? S.gen(specs[:block]) : Utils.constantly(nil)
      arg_block_gen = Gen.tuple(args_gen, block_gen)

      generator_guard = ->(genned_val) { S.valid?(specs[:args], genned_val) }

      ret = S::Test.send(:rantly_quick_check, arg_block_gen, iterations, generator_guard) { |(args, block)|
        call_valid?(f, specs, args, block)
      }

      smallest = ret[:shrunk] && ret[:shrunk][:smallest]
      smallest || f
    end

    def self.call_valid?(f, specs, args, block)
      cargs = S.conform(specs[:args], args)
      return if S.invalid?(cargs)

      if specs[:block]
        cblock = S.conform(specs[:block], block)
        return if S.invalid?(cblock)
      end

      ret = f.call(*args, &block)

      cret = S.conform(specs[:ret], ret)
      return if S.invalid?(cret)

      return true unless specs[:fn]

      S.pvalid?(specs[:fn], :args => cargs, :block => block, :ret => cret)
    end
  end
end
