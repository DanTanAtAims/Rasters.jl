
"""
    AbstractGeoArray <: DimensionalData.AbstractDimArray

Abstract supertype for objects that wrap an array (or location of an array) 
and metadata about its contents. It may be memory or hold a `FileArray`, which
holds the filename, and is only opened when required.

`AbstractGeoArray`s inherit from [`AbstractDimArray`]($DDarraydocs)
from DimensionalData.jl. They can be indexed as regular Julia arrays or with
DimensionalData.jl [`Dimension`]($DDdimdocs)s. They will plot as a heatmap in
Plots.jl with correct coordinates and labels, even after slicing with
`getindex` or `view`. `getindex` on a `AbstractGeoArray` will always return
a memory-backed `GeoArray`.
"""
abstract type AbstractGeoArray{T,N,D,A} <: AbstractDimensionalArray{T,N,D,A} end

# Interface methods ###########################################################
"""
    missingval(x)

Returns the value representing missing data in the dataset
"""
function missingval end
missingval(x) = missing
missingval(A::AbstractGeoArray) = A.missingval

filename(A::AbstractGeoArray) = filename(data(A))

cleanreturn(A::AbstractGeoArray) = modify(cleanreturn, A)
cleanreturn(x) = x

isdisk(A::AbstractGeoArray) = parent(A) isa DiskArrays.AbstractDiskArray
ismem(A::AbstractGeoArray) = !isdisk(A)

function Base.:(==)(A::AbstractGeoArray{T,N}, B::AbstractGeoArray{T,N}) where {T,N} 
    size(A) == size(B) && all(A .== B)
end

"""
    crs(x)

Get the projected coordinate reference system of a `Y` or `X` `Dimension`,
or of the `Y`/`X` dims of an `AbstractGeoArray`.

For [`Mapped`](@ref) mode this may be `nothing` as there may be no projected
coordinate reference system at all.
"""
function crs end
function crs(obj)
    if hasdim(obj, Y)
        crs(dims(obj, Y))
    elseif hasdim(obj, X)
        crs(dims(obj, X))
    else
        error("No Y or X dimension, crs not available")
    end
end
crs(dim::Dimension) = crs(mode(dim))

"""
    mappedcrs(x)

Get the mapped coordinate reference system for the `Y`/`X` dims of an array.

In [`Projected`](@ref) mode this is used to convert [`Selector`]($DDselectordocs)
values form the mappedcrs defined projection to the underlying projection, and to
show plot axes in the mapped projection.

In `Mapped` mode this is the coordinate reference system of the index values.
"""
function mappedcrs end
function mappedcrs(obj)
    if hasdim(obj, Y)
        mappedcrs(dims(obj, Y))
    elseif hasdim(obj, X)
        mappedcrs(dims(obj, X))
    else
        error("No Y or X dimension, mappedcrs not available")
    end
end
mappedcrs(dim::Dimension) = mappedcrs(mode(dim))

for f in (:mappedbounds, :projectedbounds, :mappedindex, :projectedindex)
    @eval ($f)(A::AbstractGeoArray, dims_) = ($f)(dims(A, dims_))
    @eval ($f)(A::AbstractGeoArray) = ($f)(dims(A))
end

# DimensionalData methods

DD.units(A::AbstractGeoArray) = get(metadata(A), :units, nothing)
# Rebuild all types of AbstractGeoArray as GeoArray
function DD.rebuild(
    A::AbstractGeoArray, data, dims::Tuple, refdims, name,
    metadata, missingval=missingval(A)
)
    GeoArray(data, dims, refdims, name, metadata, missingval)
end
function DD.rebuild(A::AbstractGeoArray;
    data=data(A), dims=dims(A), refdims=refdims(A), name=name(A),
    metadata=metadata(A), missingval=missingval(A)
)
    rebuild(A, data, dims, refdims, name, metadata, missingval)
end

function DD.DimTable(As::Tuple{<:AbstractGeoArray,Vararg{<:AbstractGeoArray}}...)
    DimTable(DimStack(map(read, As...)))
end

# DiskArrays methods

DiskArrays.eachchunk(A::AbstractGeoArray) = DiskArrays.eachchunk(parent(A))
DiskArrays.haschunks(A::AbstractGeoArray) = DiskArrays.haschunks(parent(A))
function DA.readblock!(A::AbstractGeoArray, dst, r::AbstractUnitRange...)
    DA.readblock!(parent(A), dst, r...)
end
function DA.writeblock!(A::AbstractGeoArray, src, r::AbstractUnitRange...) 
    DA.writeblock!(parent(A), src, r...)
end

# Base methods

Base.parent(A::AbstractGeoArray) = data(A)

"""
    open(f, A::AbstractGeoArray; write=false)

`open` is used to open any `AbstractGeoArray` and do multiple operations
on it in a safe way. The `write` keyword opens the file in write mode so that it
can be altered on disk using e.g. a broadcast.

`f` is a method that accepts a single argument - an `GeoArray` object
which is just an `AbstractGeoArray` that holds an open disk-based object.
Often it will be a `do` block:

```julia
# A is an `GeoArray` wrapping the opened disk-based object.
open(GeoArray(filepath); write=true) do A
    mask!(A; to=maskfile)
    A[I...] .*= 2
    # ...  other things you need to do with the open file
end
```

By using a do block to open files we ensure they are always closed again
after we finish working with them.
"""
function Base.open(f::Function, A::AbstractGeoArray; kw...)
    # Open FileArray to expose the actual dataset object, even inside nested wrappers
    select = FileArray
    ignore = Union{Dict,Set,Base.MultiplicativeInverses.SignedMultiplicativeInverse}
    fa = Flatten.flatten(parent(A), select, ignore)
    if fa == ()
        f(GeoArray(parent(A), dims(A), refdims(A), name(A), metadata(A), missingval(A)))
    else
        open(fa[1]; kw...) do x
            # Rewrap the opened object where the FileArray was
            d = Flatten.reconstruct(parent(A), (x,), select, ignore) 
            f(GeoArray(d, dims(A), refdims(A), name(A), metadata(A), missingval(A)))
        end
    end
end
Base.write(A::T) where T <: AbstractGeoArray = write(filename(A), A)

# Concrete implementation ######################################################

"""
    GeoArray <: AbsractGeoArray

    GeoArray(filepath::AbstractString, dims; kw...)
    GeoArray(A::AbstractArray{T,N}, dims; kw...)
    GeoArray(A::AbstractGeoArray; kw...)

A generic [`AbstractGeoArray`](@ref) for spatial/raster array data. It may hold
memory-backed arrays or [`FileArray`](@ref), that simply holds the `String` path
to an unopened file. This will only be opened lazily when it is indexed with `getindex`
or when `read(A)` is called. Broadcasting, taking a view, reversing and most other 
methods _do not_ load data from disk: they are applied later, lazily.

# Keywords

- `data`: can replace the data in an `AbstractGeoArray`
- `dims`: `Tuple` of `Dimension`s for the array.
- `refdims`: `Tuple of` position `Dimension`s the array was sliced from, defaulting to `()`.
- `key`: `Symbol` key to desired layer in a multi-layer dataset, when a `filpath` is used.
- `name`: `Symbol` name for the array. `key` is used by default when a filepath `String` is pased in.
- `missingval`: value reprsenting missing data, normally detected form the file. Set manually
    when you know the value is not specified or is incorrect. This will *not* change any
    values in the raster, it simply assigns which value is treated as missing. To replace all of
    the missing values in the raster, use [`replace_missing`](@ref).
- `metadata`: `ArrayMetadata` object for the array, or `NoMetadata()`.
- `crs`: the coordinate reference system of  the objects `XDim`/`YDim` dimensions. 
    Only set this if you know the detected crs is incrorrect, or it is not present in
    the file.
- `mappedcrs`: the mapped coordinate reference system of the objects `XDim`/`YDim` dimensions.
    for `Mapped` lookups these are the actual values of the index. For `Projected` lookups
    this can be used to index in eg. `EPSG(4326)` lat/lon values, having it converted automatically.
    Only set this if the detected `mappedcrs` in incorrect, or the file does not have a `mappedcrs`,
    e.g. a tiff.
"""
struct GeoArray{T,N,D<:Tuple,R<:Tuple,A<:AbstractArray{T,N},Na,Me,Mi} <: AbstractGeoArray{T,N,D,A}
    data::A
    dims::D
    refdims::R
    name::Na
    metadata::Me
    missingval::Mi
end
function GeoArray(A::AbstractArray, dims::Tuple;
    refdims=(), name=Symbol(""), metadata=NoMetadata(), missingval=missing,
)
    GeoArray(A, DD.formatdims(A, dims), refdims, name, metadata, missingval)
end
function GeoArray(A::AbstractArray;
    dims, refdims=(), name=Symbol(""), metadata=NoMetadata(), missingval=missing
)
    GeoArray(A, DD.formatdims(A, dims), refdims, name, metadata, missingval)
end
function GeoArray(A::AbstractGeoArray;
    data=data(A), dims=dims(A), refdims=refdims(A),
    name=name(A), metadata=metadata(A), missingval=missingval(A)
)
    GeoArray(data, dims, refdims, name, metadata, missingval)
end
function GeoArray(filename::AbstractString; key=nothing, kw...)
    isfile(filename) || error("File not found: $filename")
    _open(filename) do ds
        key = filekey(ds, key)
        GeoArray(ds, filename, key; kw...)
    end
end
# For loading opened datasets
function GeoArray(ds, filename::AbstractString, key=nothing;
    crs=nothing, mappedcrs=nothing, dims=nothing, refdims=(),
    name=Symbol(key isa Nothing ? "" : string(key)),
    metadata=metadata(ds), missingval=missingval(ds), write=false,
    source=_sourcetype(filename)
)
    crs = defaultcrs(source, crs)
    mappedcrs = defaultmappedcrs(source, mappedcrs)
    dims = dims isa Nothing ? DD.dims(ds, crs, mappedcrs) : dims
    data = FileArray(ds, filename; key, write)
    GeoArray(data, dims, refdims, name, metadata, missingval)
end

@propagate_inbounds function Base.setindex!(A::GeoArray, x, I::DD.StandardIndices...)
    setindex!(data(A), x, I...)
end

filekey(ds, key) = key
filekey(filename::String) = Symbol(splitext(basename(filename))[1])

# Precompile
precompile(GeoArray, (String,))

@deprecate geoarray(args...; kw...) GeoArray(args...; kw...)
