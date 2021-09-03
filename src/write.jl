"""
    Base.write(filename::AbstractString, A::AbstractGeoArray; kw...)

Write an [`AbstractGeoArray`](@ref) to file, guessing the backend from the file extension.

Keyword arguments are passed to the `write` method for the backend.
"""
function Base.write(
    filename::AbstractString, A::AbstractGeoArray; kw...
)
    write(filename, _sourcetype(filename), A; kw...)
end

"""
    Base.write(filename::AbstractString, T::Type{<:AbstractGeoArray}, s::AbstractGeoStack)

Write any [`AbstractGeoStack`](@ref) to file, guessing the backend from the file extension.

Keyword arguments are passed to the `write` method for the backend.

If the source can't be saved as a stack-like object, individual array layers will be saved.
"""
function Base.write(filename::AbstractString, s::AbstractGeoStack; suffix=nothing, kw...)
    base, ext = splitext(filename)
    T = _sourcetype(filename)
    if haslayers(T)
        write(filename, _sourcetype(filename), s; kw...)
    else
        # Otherwise write separate arrays
        if suffix === nothing
            suffix = map(k -> string("_", k), keys(s))
        end
        for sfx in suffix
            fn = joinpath(string(base, sfx, ext))
            write(fn, _sourcetype(filename), s[key])
        end
    end
end

haslayers(T) = false
