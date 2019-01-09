module TypeFreeze

using InteractiveUtils  # For examining the outputs

# This is the idea we want to implement:
function widened_typeof_helper(::Type{T}) where {T}
    println("typed_helper(::$T)")
    widen(T)
end
function widened_typeof(::T) where {T}
    val = widened_typeof_helper(T)
    @eval widened_typeof(::$T) = $val
    return val
end

# Before it's called and memoized, the function is several lines long:
length((@code_typed widened_typeof(6))[1].code) > 1
# Calling the function memoizes its result as a newly defined method.
widened_typeof(Int64(3))
# Now, the entire body of the function is simply `return Int128`
(@code_typed widened_typeof(6))[1].code == [:(return $(Int128))]

include("utilities.jl")

"""
    @typefreeze function f(x) ... end

"Freezes" the output of a function for given parameter types.

Provides function output memoization, keyed by input types. This is implemented using
Julia's built-in dispatch mechanisms, by using `@eval` to generate a new method for each
unique input types tuple, whose function body is simply the return value.

This memoization occurs at the end of the first invocation, such that the function has a
one-time cost not unlike the compilation penalty incurred when type inference attempts to
compile a new instantiation of a method for new input parameters.
"""
macro typefreeze(funcexpr)
    dump(funcexpr)
    @assert funcexpr.head == :function
    name = funcexpr.args[1].args[1]
    escname = esc(name)
    args = funcexpr.args[1].args[2:end]
    types = argtypes(args)
    names = argnames(args)
    function_params = paramexprs(args)
    escargs = [esc(a) for a in args]
    body = esc(funcexpr.args[2])
    methods_helpername = gensym(name)
    quote
        function func_generator($(escargs...))
            $body
        end
        function $(esc(methods_helpername))($(function_params...))
            types = [$(types...)]
            val = func_generator($(names...))
            typedargs = [Expr(Symbol("::"), t) for t in types]
            #@eval $finalcall = $(Expr(:$, :val))
            @eval @inline $methods_helpername($(Expr(:$, :(typedargs...)))) = $(Expr(:$, :val))
            return val
        end
        # The actual function simply delegates to the helper above
        function $escname($(function_params...))
            $(esc(methods_helpername))($(names...))
        end
    end
end

# -------- Illustration: ----------
# As an example, `@typefreeze function tzero(t::Tuple) Tuple(zero(x) for x in t) end` would
# produce the following code:
tzero_generator(t::Tuple) = Tuple(zero(x) for x in t)
function tzero_methods_helper(t::Tuple)
    val = tzero_generator(t)
    @eval @inline tzero_methods_helper(::$(typeof(t))) = $val
    return val
end
tzero(t::Tuple) = tzero_methods_helper(t)

tzero((1, 3, 2)) == (0, 0, 0)
tzero((1.0,)) == (0.0,)
# And the function is entirely memoized away:
@code_typed(tzero((1.0,)))[1].code == [:(return $((0.0,)))]

# ------- Tests: --------

@typefreeze function foo(x::Int8, y, ::Number)
    return x*y
end
methods(foo)
@code_typed foo(Int8(2), 5.0, 3)
foo(Int8(2), 5.0, 3)
methods(foo)
@code_typed foo(Int8(2), 5.0, 3)
foo(Int8(2), 4, 3)
foo(Int8(2), 6, 3)

@code_typed(foo(Int8(2), 5, 3))[1].code == [:(return $(8))]


# Real example:

# FixedPointDecimals.max_exp10(::Type{T}) where T
# In that package, this is manually "frozen" after its definition via manual @evals:
#   @eval max_exp10(::Type{Int128}) = $(max_exp10(Int128))  # Freeze for Int128, since it doesn't fold.

@typefreeze function max_exp10(x)  # Note this should of course be ::Type{T} where T, but that doesn't work yet.
    T = typeof(x)
    W = widen(T)
    type_max = W(typemax(T))

    powt = one(W)
    ten = W(10)
    exponent = 0

    while type_max > powt
        powt *= ten
        exponent += 1
    end

    exponent - 1
end

max_exp10(Int8(0))
@code_typed max_exp10(Int8(0))
# Even though this creates a BigInt, it can still be const-folded!
# This process is basically "manual (const) folding", where you're demanding folding even
# when the input might not be (provably) Const.
max_exp10(Int128(0))
@code_typed max_exp10(Int128(0))



end
