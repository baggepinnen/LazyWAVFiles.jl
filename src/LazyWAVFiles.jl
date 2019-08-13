module LazyWAVFiles
    using WAV, LazyArrays
    export LazyWAVFile, DistributedWAVFile
    struct LazyWAVFile{T,N,S<:Tuple} <: AbstractArray{T,N}
        path::String
        size::S
    end
    function LazyWAVFile(path)
        r = wavread(path, format="native", subrange=1)[1]
        s = wavread(path, format="size")
        T = eltype(r)
        N = length(s[2])
        if N == 1
            s = (s[1],)
        end
        LazyWAVFile{T,N,typeof(s)}(path, s)
    end
    Base.size(f::LazyWAVFile) = f.size
    Base.size(f::LazyWAVFile{T,N},i) where {T,N} = i > N ? 1 : f.size[i]
    Base.length(f::LazyWAVFile) = prod(f.size)

    Base.getindex(f::LazyWAVFile{T,N}, i::Number) where {T,N} = wavread(f.path, format="native", subrange=i:i)[1][1]::T
    Base.getindex(f::LazyWAVFile{T,1}, i::AbstractRange) where {T} = vec(wavread(f.path, format="native", subrange=i)[1])::Array{T,1}
    Base.getindex(f::LazyWAVFile{T,2}, i::AbstractRange) where {T} = wavread(f.path, format="native", subrange=i)[1]::Array{T,2}

    Base.getindex(f::LazyWAVFile{T,1}, ::Colon) where {T} = vec(wavread(f.path, format="native")[1])::Array{T,1}
    Base.getindex(f::LazyWAVFile{T,2}, ::Colon) where {T} = wavread(f.path, format="native")[1]::Array{T,2}

    Base.eltype(f::LazyWAVFile{T}) where T = T
    Base.ndims(f::LazyWAVFile{T,N}) where {T,N} = N
    Base.show(io::IO, f::LazyWAVFile{T,N,S}) where {T,N,S} = println(io, "LazyWAV{$T, $N, $(f.size)}: ", f.path)


    struct DistributedWAVFile{T,N,L} <: AbstractArray{T,N}
        files::Vector{LazyWAVFile{T,N}}
        lazyarray::L
    end
    function DistributedWAVFile(folder::String)
        files = filter(readdir(folder)) do file
            file[end-2:end] == "wav"
        end
        files = sort(files)
        files = LazyWAVFile.(joinpath.(Ref(folder), files))
        DistributedWAVFile(files)
    end
    function DistributedWAVFile(files)
        lazyarray = Vcat(files...)
        DistributedWAVFile{eltype(files[1]), ndims(files[1]), typeof(lazyarray)}(files, lazyarray)
    end
    Base.length(f::DistributedWAVFile) = sum(length, f.files)
    Base.size(f::DistributedWAVFile{T,N}) where {T,N} = ntuple(i->sum(x->size(x,i), f.files), N)

    Base.show(io::IO, f::DistributedWAVFile{T,N}) where {T,N} = println(io, "DistributedWAVFile{$T, $N} with $(length(f.files)) files")

    Base.getindex(df::DistributedWAVFile, i...) = getindex(df.lazyarray, i...)

    Base.vcat(dfs::DistributedWAVFile...) = DistributedWAVFile(reduce(vcat, getfield.(dfs, :files)))

end
