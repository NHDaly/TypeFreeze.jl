
#   # This is the idea:
#   function expensive_helper()
#       println("...Expensive calculation...")
#   end
#   function expensive()
#       @eval expensive() = $(expensive_helper())
#       return @eval expensive()
#   end
#
#   println("Calling the first time:")
#   expensive()
#
#   println("Calling the second time:")
#   expensive()
#
#   #function foo_helper(::Val{x}, ::Val{y}) where {x, y}
#   #    println("foo_helper1")
#   #    @show x,y
#   #end
#   #function foo_helper2(x::Val, y::Val)
#   #    println("foo_helper2")
#   #    @eval foo_helper2(x,y) = $(foo_helper(x,y))
#   #    return @eval foo_helper2($x,$y)
#   #end
#   #function foo(x,y)
#   #    foo_helper2(Val(x),Val(y))
#   #end
#   #
#   #println("Calling the first time:")
#   #foo(1,2)
#   #println("Calling the second time:")
#   #foo(1,2)
#   #println("Calling with new values:")
#   #foo(2,2)
#   #println("Calling the second time:")
#   #foo(1,2)
#
#   macro freeze(funcexpr)
#       dump(funcexpr)
#       @assert funcexpr.head == :function
#       name = esc(funcexpr.args[1].args[1])
#       args = funcexpr.args[1].args[2:end]
#       escargs = [esc(a) for a in funcexpr.args[1].args[2:end]]
#       body = esc(funcexpr.args[1].args[2])
#       argtypes_call = :(typeof.($args))
#       innerfunc = :($name($argtypes_call) = 3)
#       quote
#           function funchelper($(escargs...))
#               $body
#           end
#           function $name($(escargs...))
#               eval(Expr(:quote, $innerfunc))
#                 #funchelper($(args...))
#               #return eval($name($(args...)))
#           end
#       end
#   end
#
#   @freeze function bar(x,y)
#       x,y
#   end
#
#   bar(3,3)
#
#



# ========================

function typed_helper(::Type{T}) where {T}
    println("typed_helper(::$T)")
    widen(T)
end
function typed(::T) where {T}
    val = typed_helper(T)
    @eval typed(::$T) = $val
    return val
end

typed(Int64(3))

function argnames(args::Array)
    tmpcount = 0
    out = []
    for a in args
        name = argname(a)
        if name == nothing
            tmpcount += 1
            name = Symbol("_$tmpcount")
        end
        push!(out, name)
    end
    out
end
argname(x::Symbol) = esc(x)
function argname(e::Expr)
    @assert e.head == Symbol("::")
    return length(e.args) == 2 ? esc(e.args[1]) : nothing
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
paramexpr(name, e::Symbol) = esc(e)
paramexpr(name, e::Expr) = :($(name)::$(argtype(e)))

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
    quote
        function funchelper($(escargs...))
            $body
        end
        function $escname($(function_params...))
            types = [$(types...)]
            val = funchelper($(names...))
            typedargs = [Expr(Symbol("::"), t) for t in types]
            #@eval $finalcall = $(Expr(:$, :val))
            @eval $name($(Expr(:$, :(typedargs...)))) = $(Expr(:$, :val))
            return val
        end
    end
end

@typefreeze function f(x::Int8, y, ::Number)
    return x*y
end
@code_typed f(Int8(2), 5.0, 3)
methods(f)



#
#printer(x::Number) = typeof(x)
#printer(::Int64) = Int
#
#printer(2)
#
#
#macro argnames()
#    quote function $(esc(:foo))(_x1, $(esc(:_x1))) end
#    end
#end
#
#@argnames()
