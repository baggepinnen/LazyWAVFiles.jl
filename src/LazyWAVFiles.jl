module LazyWAVFiles
using WAV, LazyArrays
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

Base.getindex(f::LazyWAVFile{T,N}, i::Integer) where {T,N} = wavread(f.path, format="native", subrange=i:i)[1][1]::T

Base.getindex(f::LazyWAVFile{T,N}, i::Integer,j) where {T,N} = wavread(f.path, format="native", subrange=i:i)[1][j]
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
    lazyarray::L
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
function DistributedWAVFile(files,fs)
    lazyarray = Vcat(files...)
    try
        return DistributedWAVFile{eltype(files[1]), ndims(files[1]), typeof(lazyarray), typeof(fs)}(files, lazyarray, fs)
    catch e
        @error "Creating distributed WAV file failed. This can happen if the wav-files in the folder have different number of channels."
        rethrow(e)
    end
end
Base.length(f::DistributedWAVFile) = sum(length, f.files)
Base.size(f::DistributedWAVFile{T,N}) where {T,N} = ntuple(i->sum(x->size(x,i), f.files), N)

Base.show(io::IO, ::MIME"text/plain", f::DistributedWAVFile{T,N}) where {T,N} = println(io, "DistributedWAVFile{$T, $N} with $(length(f.files)) files, $(length(f)) total datapoints and samplerate $(f.fs)")

Base.getindex(df::DistributedWAVFile, i...) = getindex(df.lazyarray, i...)

function Base.vcat(dfs::DistributedWAVFile...)
    fs = dfs[1].fs
    any(x->x.fs != fs, dfs) && error("Distributed WAV files have different sample rates.")
    DistributedWAVFile(reduce(vcat, getfield.(dfs, :files)), fs)
end


end
