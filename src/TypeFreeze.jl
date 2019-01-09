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
    typefreeze_helper(funcexpr, __module__)
end
function typefreeze_helper(funcexpr, __module__)
    dump(funcexpr)
    @assert(funcexpr.head == :function || Base.is_short_function_def(funcexpr))
    signature = funcexpr.args[1]
    func_callexpr = call_expr(signature)
    name = func_callexpr.args[1]

    escname = esc(name)
    args = func_callexpr.args[2:end]
    function_params = paramexprs(args)
    names = argnames(function_params)
    escnames = [esc(n) for n in argnames(function_params)]

    @show function_params

    # Special case for Type{T} types:
    #if isa(v, Expr) && v.head == :curly && v.args[1] == :Type
    #    v = v.args[2]
    #end
    #v


    esctypes = [esc(t) for t in argtypes(function_params)]
    escargs = [esc(a) for a in args]
    body = funcexpr.args[2]
    escbody = esc(body)

    main_signature = deepcopy(signature)
    call_expr(main_signature).args[2:end] = function_params

    # TODO: There is a bug in the julia macro-expander, preventing escaping the entire signature.
    # Therefore, for now, we have to manually escape its internals
    methods_helpername = gensym("$(name)_methods")
    methods_signature = deepcopy(main_signature)
    call_expr(methods_signature).args[1] = esc(methods_helpername)
    call_expr(methods_signature).args[2:end] = [esc(p) for p in function_params]
    # Escape the type parameters in where clauses (TODO: remove when bug is fixed)
    sigexpr = methods_signature
    while sigexpr.head != :call
        sigexpr.args[2] = esc(sigexpr.args[2])
        sigexpr = sigexpr.args[1]
    end

    generator_helpername = gensym("$(name)_generator")
    generator_signature = deepcopy(signature)
    call_expr(generator_signature).args[1] = generator_helpername

    quote
        # This is the user's original function:
        $(esc(Expr(:function, generator_signature, body)))
        # This is the new implementation, which tacks new methods onto itself for each new
        # argument types tuple.
        # TODO: when the macro expander bug is fixed, esc the signature here instead.
        $(Expr(:function, (methods_signature), quote
            # Get actual return value from user's function:
            val = $(esc(generator_helpername))($(escnames...))
            # Compute the actual runtime types of the input arguments:
            types = [$(esctypes...)]
            typedargs = Tuple(Expr(Symbol("::"), t) for t in types)
            @eval $__module__ @inline $methods_helpername($(Expr(:$, :(typedargs...)))) = $(Expr(:$, :val))
            #@eval @show methods($methods_helpername)
            return val
        end))
        # The actual function simply delegates to the helper above
        # TODO: when the macro expander bug is fixed, esc the signature here instead.
        $(esc(Expr(:function, (main_signature), quote
            $methods_helpername($(names...))
        end)))
    end
end

#out1 = typefreeze_helper(:(myzero(x::Type{T}) where T = x), @__MODULE__)
@macroexpand @typefreeze myzero(x::Type{T}) where T = x

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

@typefreeze function max_exp10(::Type{T}) where T
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

max_exp10(Int8)
@code_typed max_exp10(Int8)
# Even though this creates a BigInt, it can still be const-folded!
# This process is basically "manual (const) folding", where you're demanding folding even
# when the input might not be (provably) Const.
max_exp10(Int128)
@code_typed max_exp10(Int128)



end
