module RAIGenerated
using InteractiveUtils

include("typefreeze.jl")

"""
    @rAI_generated function f(x) :(x+1) end

Implements the same functionality as @generated, but using `@eval`, so that it is guaranteed
to generate a new function for given type parameters exactly once.
"""
macro rAI_generated(f)
    if isa(f, Expr) && (f.head === :function || Base.is_short_function_def(f))
        body = f.args[2]
        lno = body.args[1]
        return gen_eval_f(f)
    else
        error("invalid syntax; @generated must be used with a function definition")
    end
end

function raw_argnames(args::Array)
    tmpcount = 0
    out = []
    for a in args
        name = raw_argname(a)
        if name == nothing
            tmpcount += 1
            name = Symbol("_$tmpcount")
        end
        push!(out, name)
    end
    out
end
raw_argname(x::Symbol) = x
function raw_argname(e::Expr)
    @assert e.head == Symbol("::")
    return length(e.args) == 2 ? e.args[1] : nothing
end

function gen_eval_f(funcexpr::Expr)
    dump(funcexpr)
    name = funcexpr.args[1].args[1]
    escname = esc(name)
    args = funcexpr.args[1].args[2:end]
    types = argtypes(args)
    names = raw_argnames(args)
    esc_argnames = argnames(args)
    function_params = paramexprs(args)
    escargs = [esc(a) for a in args]
    body = esc(funcexpr.args[2])
    quote
        function funchelper($(escargs...))
            $body
        end
        function $escname($(function_params...))
            names = $names
            types = [$((:typeof(x) for x in params)...)]
            generated_body = funchelper(types...)
            typedargs = [Expr(Symbol("::"), names[i], types[i]) for i in 1:$(length(args))]
            #@eval $finalcall = $(Expr(:$, :val))
            @eval $name($(Expr(:$, :(typedargs...)))) = $(Expr(:$, :generated_body))
            return @eval $name($([Expr(:$, n) for n in names]...))
        end
    end
end
gen_eval_f(:(f(x::Int64) = 3))

# EXAMPLE:
# This is what the macro expands to:
function bar(x)
    names = [:x]
    types = [typeof(x)]
    gen_body = bar_helper(types...)
    # Real @generated creates method instances, not methods
    #  Consequence: allows you to redefine body of bar() in the future.
    # Also: slower! Dynamic dispatch is slow, and gets slower w/ more methods
    @eval bar(x::types...) = $(gen_body)
    return @eval bar(x)
end

@rAI_generated function bar(x)
    if x <: Integer
        return :(x ^ 2)
    else
        return :(x)
    end
end

# Generated functions in general:
#  - dynamic dispatch, more often, and with more methodinstances
#  - Forced to have one methodinstances per unique params type tuple
#  - Forced to know the runtime types always to have statically inferrable code

@show methods(bar)
@show bar(3.0)
@show methods(bar)
@show bar(3.0)
@show bar(3)
@code_typed bar(3.0)

# Compare with the built-in @generated, which doesn't add new methods:
# @generated function baz(x)
#     if x <: Integer
#         return :(x ^ 2)
#     else
#         return :(x)
#     end
# end
#
# @show methods(baz)
# baz(4)

end
