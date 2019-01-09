
function call_expr(signature)
    if signature.head == :call
        return signature
    end
    return call_expr(signature.args[1])
end

function argnames(args::Array)
    tmpcount = 0
    out = []
    for a in args
        name = argname(a)
        if name == nothing
            tmpcount += 1
            name = gensym("_$tmpcount")
        end
        push!(out, name)
    end
    out
end
argname(x::Symbol) = (x)
function argname(e::Expr)
    @assert e.head == Symbol("::")
    return length(e.args) == 2 ? (e.args[1]) : nothing
end
argtypes(args::Array) = [argtype(a) for a in args]
argtype(x::Symbol) = :(typeof($x))
function argtype(e::Expr)
    @assert e.head == Symbol("::")
    e.args[end]
end

function paramexprs(arr::Array)
    names = argnames(arr)
    return [paramexpr(names[i], arr[i]) for i in 1:length(arr)]
end
paramexpr(name, e::Symbol) = (e)
paramexpr(name, e::Expr) = :($(name)::$(argtype(e)))
