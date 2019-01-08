module RAIGenerated
using InteractiveUtils

include("typefreeze.jl")

@generated function bar(x)
    if x <: Integer
        return :(x ^ 2)
    else
        return :(x)
    end
end

bar(4)

macro rAI_generated(f)
    if isa(f, Expr) && (f.head === :function || Base.is_short_function_def(f))
        body = f.args[2]
        lno = body.args[1]
        return gen_eval_f(f)
    else
        error("invalid syntax; @generated must be used with a function definition")
    end
end

function gen_eval_f(funcexpr::Expr)
    dump(funcexpr)
    name = funcexpr.args[1].args[1]
    escname = esc(name)
    args = funcexpr.args[1].args[2:end]
    types = argtypes(args)
    names = argnames(args)
    function_params = paramexprs(args)
    escargs = [esc(a) for a in args]
    body = esc(funcexpr.args[2])
    quote
        function funchelper($(escargs...))
            $body
        end
        function $escname($(function_params...))
            types = [$(types...)]
            val = funchelper(types...)
            typedargs = [Expr(Symbol("::"), t) for t in types]
            #@eval $finalcall = $(Expr(:$, :val))
            @eval $name($(Expr(:$, :(typedargs...)))) = $(Expr(:$, :val))
            return val
        end
    end
end
gen_eval_f(:(f(x::Int64) = 3))

@rAI_generated function baz(x)
    if x <: Integer
        return :(x ^ 2)
    else
        return :(x)
    end
end
@code_typed baz(3)

end
