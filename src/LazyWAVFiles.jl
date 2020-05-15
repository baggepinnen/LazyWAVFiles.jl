"""
Treat WAV files as lazy arrays stored on disk.

Documentation: https://github.com/baggepinnen/LazyWAVFiles.jl

## Quick start
### LazyWAVFile
```
f1 = LazyWAVFile(joinpath(d,"f1.wav"))
f1[1]
f1[1:5]
size(f1)
f1.fs # Get the sample rate

[f1; f2] # Creates a `DistributedWAVFile`
```

### DistributedWAVFile
```
df = DistributedWAVFile(folder_path)
df[1]
df[1:12]
df[:]

size(df) # Other array functions are defined as well
length(df)
df.fs    # Get the sample rate
```
"""
module LazyWAVFiles
using WAV, BlockArrays
export LazyWAVFile, DistributedWAVFile, path

struct LazyWAVFile{T,N,FS,S<:Tuple} <: AbstractArray{T,N}
    path::String
    size::S
    fs::FS
end
function LazyWAVFile(path)
    r,fs = wavread(path, format="native", subrange=1)
    s = wavread(path, format="size")
    T = eltype(r)
    dim = s[2]
    if dim == 1
        s = (s[1],)
    end
    LazyWAVFile{T,dim,typeof(fs),typeof(s)}(path, s, fs)
end

Base.size(f::LazyWAVFile) = f.size
Base.size(f::LazyWAVFile{T,N},i) where {T,N} = i > N ? 1 : f.size[i]
Base.length(f::LazyWAVFile) = prod(f.size)
path(f::LazyWAVFile) = f.path

function Base.copyto!(dst::SubArray{T,N,Array{T,N},Tuple{UnitRange{Int64}}}, sa::SubArray{T,N,<:LazyWAVFile{T,N}}) where {T,N}
    copyto!(dst, sa.parent[sa.indices...])
end

function Base.copyto!(dst::AbstractArray, rd::Int, src::LazyWAVFile, rs::Int, N::Int)
    dst[rd:rd+N-1] .= src[rs:rs+N-1]
end

Base.getindex(f::LazyWAVFile{T,N}, i::Integer) where {T,N} = wavread(f.path, format="native", subrange=i:i)[1][1]::T

Base.getindex(f::LazyWAVFile{T,N}, i::Integer,j::Integer) where {T,N} = wavread(f.path, format="native", subrange=i:i)[1][j]::T
Base.getindex(f::LazyWAVFile{T,N}, i::Integer,j::Union{Colon,AbstractRange}) where {T,N} = wavread(f.path, format="native", subrange=i:i)[1][1,j]::Array{T,1}
Base.getindex(f::LazyWAVFile{T,N}, i::Union{Colon,AbstractRange},j::Integer) where {T,N} = wavread(f.path, format="native", subrange=i)[1][:,j]::Array{T,1}
Base.getindex(f::LazyWAVFile{T,N}, i,j) where {T,N} = wavread(f.path, format="native", subrange=i)[1][:,j]
Base.getindex(f::LazyWAVFile{T,1}, i::AbstractRange) where {T} = vec(wavread(f.path, format="native", subrange=i)[1])::Array{T,1}
Base.getindex(f::LazyWAVFile{T,N}, i::AbstractRange) where {T,N} = wavread(f.path, format="native", subrange=i)[1]::Array{T,2}

Base.getindex(f::LazyWAVFile{T,1}, ::Colon) where {T} = vec(wavread(f.path, format="native")[1])::Array{T,1}
Base.getindex(f::LazyWAVFile{T,N}, ::Colon, ::Colon) where {T,N} = wavread(f.path, format="native")[1]::Array{T,2}

Base.eltype(f::LazyWAVFile{T}) where T = T
Base.ndims(f::LazyWAVFile{T,N}) where {T,N} = N
Base.show(io::IO, f::LazyWAVFile{T,N,S}) where {T,N,S} = println(io, "LazyWAV{$T, $N, $(f.size), fs=$(f.fs)}: ", f.path)


struct DistributedWAVFile{T,N,L,FS} <: AbstractArray{T,N}
    files::Vector{LazyWAVFile{T,N,FS}}
    blockarray::L
    fs::FS
end
function DistributedWAVFile(folder::String)
    files = filter(readdir(folder)) do file
        lowercase(file[end-2:end]) == "wav"
    end
    isempty(files) && error("Found no wav files in the specified path: $folder")
    files = sort(files)
    files = LazyWAVFile.(joinpath.(Ref(folder), files))
    fs0 = files[1].fs
    if !all(x->x.fs==fs0, files)
        error("WAV files in $folder have different sample rates.")
    end
    DistributedWAVFile(files,fs0)
end
function DistributedWAVFile(files::AbstractVector{L},fs) where L <: LazyWAVFile{T,N} where {T,N}
    blockarray = mortar(files)
    try
        return DistributedWAVFile{eltype(files[1]), ndims(files[1]), typeof(blockarray), typeof(fs)}(files, blockarray, fs)
    catch e
        @error "Creating distributed WAV file failed. This can happen if the wav-files in the folder have different number of channels."
        rethrow(e)
    end
end
Base.length(f::DistributedWAVFile) = sum(length, f.files)
Base.size(f::DistributedWAVFile{T,N}) where {T,N} = ntuple(i->sum(x->size(x,i), f.files), N)

Base.show(io::IO, ::MIME"text/plain", f::DistributedWAVFile{T,N}) where {T,N} = println(io, "DistributedWAVFile{$T, $N} with $(length(f.files)) files, $(length(f)) total datapoints and samplerate $(f.fs)")

function blockindexranges(bindices::Vector{BlockIndex{1}})
    indices = first.((x -> x.I).(bindices))
    blks = unique(indices)
    biranges = BlockArrays.BlockIndexRange{1,Tuple{UnitRange{Int}}}[]
    for blk in blks
        bindicesindices = (indices .== blk)
        push!(
            biranges,
            Block(blk)[bindices[bindicesindices][1].α[1]:bindices[bindicesindices][end].α[1]],
        )
    end
    biranges
end

function Base.getindex(blockarray::BlockVector{T}, indices::UnitRange{Int}) where T
    bindices = findblockindex.(axes(blockarray), indices)
    biranges = blockindexranges(bindices)
    x = Vector{eltype(blockarray)}(undef, length(indices))
    startind = 1
    for birange in biranges
        stopind = startind+length(birange)-1
        x[startind:stopind] = blockarray[birange]
        startind = stopind+1
    end
    x
end

Base.getindex(df::DistributedWAVFile, i...) = getindex(df.blockarray, i...)

function Base.vcat(lfs::LazyWAVFile...)
    fs = lfs[1].fs
    any(x->x.fs != fs, lfs) && error("Concatenated WAV files have different sample rates.")
    DistributedWAVFile([lfs...], fs)
end

function Base.vcat(dfs::DistributedWAVFile...)
    fs = dfs[1].fs
    any(x->x.fs != fs, dfs) && error("Distributed WAV files have different sample rates.")
    DistributedWAVFile(reduce(vcat, getfield.(dfs, :files)), fs)
end


end
