using Test, LazyWAVFiles, WAV


@testset "LazyWAVFiles" begin
    @info "Testing LazyWAVFiles"

    d = mktempdir()
    a,b = randn(Float32,10), randn(Float32,10)
    WAV.wavwrite(a, joinpath(d,"f1.wav"), Fs=8000)
    WAV.wavwrite(b, joinpath(d,"f2.wav"), Fs=8000)
    p1 = joinpath(d,"f1.wav")


    @testset "One file, one channel" begin
        @info "Testing One file, one channel"

        lf = LazyWAVFile(p1)
        @test size(lf) == (10,)
        @test path(lf) == p1
        @test lf[1] == a[1]
        @test lf[1:2] == a[1:2]
        @test lf[1:10] == a

    end


    @testset "Distributed file" begin
        @info "Testing Distributed file"

        df = DistributedWAVFile(d)
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
        @test size(lf) == (10,2)
        @test path(lf) == p3
        @test lf[1] == a[1]
        @test lf[1,2] == b[1]
        @test lf[1:10] == [a b]
    end

    @testset "Misc" begin
        @info "Testing Misc"

        @info "The following error message is intentional"
        @test_throws MethodError DistributedWAVFile(d)

    end


end
