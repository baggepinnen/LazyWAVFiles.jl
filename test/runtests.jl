using Test, LazyWAVFiles, WAV


@testset "LazyWAVFiles" begin
    @info "Testing LazyWAVFiles"

    d = mktempdir()
    a,b,c = randn(Float32,10), randn(Float32,10), randn(Float32,10)
    WAV.wavwrite(a, joinpath(d,"f1.wav"), Fs=8000)
    WAV.wavwrite(b, joinpath(d,"f2.wav"), Fs=8000)
    p1 = joinpath(d,"f1.wav")
    p2 = joinpath(d,"f2.wav")


    @testset "One file, one channel" begin
        @info "Testing One file, one channel"

        lf = LazyWAVFile(p1)
        @test lf.fs == 8000
        @test size(lf) == (10,)
        @test path(lf) == p1
        @test lf[1] == a[1]
        @test lf[1:2] == a[1:2]
        @test lf[1:10] == a
        @test lf[:] == a

        lf2 = LazyWAVFile(p2)
        df = [lf; lf2]
        @test df isa DistributedWAVFile
        @test size(df) == (20,)

    end


    @testset "Distributed file" begin
        @info "Testing Distributed file"

        df = DistributedWAVFile(d)
        @show df
        @test df.fs == 8000
        @test df[1] == a[1]
        @test df[1:2] == a[1:2]
        @test df[1:10] == a
        @test df[:] == [a;b]
        @test df[9:11] == [a[9:end];b[1]]
        @test df[[1,3,5]] == a[[1,3,5]]
        @test df[[1,3,5,12]] == [a[[1,3,5]];b[2]]


        @test size(df) == (20,)
        @test length(df) == 20
        @test length(df.files[1]) == 10
        @test length([df; df]) == 40
        @test_nowarn display(df)
        @test_nowarn display(df.files[1])
        @test ndims(df.files[1]) == 1

    end

    @testset "Multiple channels" begin
        @info "Testing Multiple channels"

        WAV.wavwrite([a b], joinpath(d,"f3.wav"), Fs=8000)
        p3 = joinpath(d,"f3.wav")
        lf = LazyWAVFile(p3)
        @test lf.fs == 8000
        @test size(lf) == (10,2)
        @test path(lf) == p3
        @test lf[1] == a[1]
        @test lf[1,2] == b[1]
        @test lf[:,1] == a
        @test lf[:,2] == b
        @test lf[1:10] == [a b]
        @test lf[:,:] == [a b]

        WAV.wavwrite([a b c], joinpath(d,"f4.wav"), Fs=8000)
        p4 = joinpath(d,"f4.wav")
        lf = LazyWAVFile(p4)
        @test lf.fs == 8000
        @test size(lf) == (10,3)
        @test path(lf) == p4
        @test lf[1] == a[1]
        @test lf[1,2] == b[1]
        @test lf[1,3] == c[1]
        @test lf[:,1] == a
        @test lf[:,2] == b
        @test lf[:,3] == c
        @test lf[1:10] == [a b c]
        @test lf[:,:] == [a b c]
        @test lf[1,:] == [a[1], b[1], c[1]]

    end

    @testset "Misc" begin
        @info "Testing Misc"

        @info "The following error message is intentional"
        @test_throws MethodError DistributedWAVFile(d)

        d = mktempdir()
        WAV.wavwrite(a, joinpath(d,"fs800.wav"), Fs=800)
        WAV.wavwrite(a, joinpath(d,"fs8000.wav"), Fs=8000)
        @test_throws ErrorException DistributedWAVFile(d)
    end


end
