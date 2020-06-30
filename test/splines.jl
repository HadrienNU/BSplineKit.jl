using BSplineKit: BSplineOrder
using BSplineKit.BSplines: multiplicity

eval_poly(x::AbstractVector, P) = [@evalpoly(t, P...) for t in x]

# Test a polynomial of degree k - 1.
# The splines should approximate the polynomial (and its derivatives) perfectly.
# This is also used to test the Interpolations module.
function test_polynomial(x, ::BSplineOrder{k}) where {k}
    # Coefficients of polynomial of degree k - 1 (see ?evalpoly).
    # P(x) = -1 + 2x - 3x^2 + 4x^3 - ...
    P = ntuple(d -> (-d)^d, Val(k))
    P′ = ntuple(d -> d * P[d + 1], Val(k - 1))    # derivative
    Pint = (0, ntuple(d -> P[d] / d, Val(k))...)  # antiderivative

    # Interpolate polynomial at `x` locations.
    itp = let y = eval_poly(x, P)
        @inferred interpolate(x, y, BSplineOrder(k))
        interpolate(x, y, k)
    end

    S = spline(itp)
    @test length(S) == length(x)

    let x = (x[2] + x[3]) / 3
        @test itp(x) == S(x)  # these are equivalent
    end

    # "incompatible lengths of B-spline basis and collocation points"
    @test_throws(DimensionMismatch,
                 Interpolations.Interpolation(basis(S), x[1:4], eltype(S)))

    # "input data has incorrect length"
    @test_throws DimensionMismatch interpolate!(itp, rand(length(x) - 1))

    S′ = diff(S, Derivative(1))
    Sint = integral(S)

    a, b = boundaries(basis(S))

    @test Sint(a) == 0  # this is an arbitrary choice
    Pint_a = @evalpoly(a, Pint...)

    # Compare values on a finer grid.
    let Nx = 9 * length(S) + 42
        x = LinRange(a, b, Nx)
        @test all(@evalpoly(x, P...) ≈ S(x) for x in x)
        @test all(@evalpoly(x, P′...) ≈ S′(x) for x in x)
        @test all(@evalpoly(x, Pint...) - Pint_a ≈ Sint(x) for x in x)
    end

    nothing
end

function test_splines(B::BSplineBasis, knots_in)
    k = order(B)
    t = knots(B)

    @testset "Knots (k = $k)" begin
        let (ka, kb) = multiplicity.(Ref(t), (1, length(t)))
            @test ka == kb == k
        end

        @test @views all(t[1:k] .== knots_in[1])
        @test @views all(t[(end - k + 1):end] .== knots_in[end])
        @test @views t[(k + 1):(end - k)] == knots_in[2:(end - 1)]
    end

    @testset "B-splines (k = $k)" begin
        N = length(B)
        @test_throws DomainError evaluate(B, 0, 0.2)
        @test_throws DomainError evaluate(B, N + 1, 0.2)

        # Verify values at the boundaries.
        @test evaluate(B, 1, t[1]) == 1.0
        @test evaluate(B, N, t[end]) == 1.0
    end

    xcol = collocation_points(B, method=Collocation.AvgKnots())
    @test xcol[1] == knots_in[1]
    @test xcol[end] == knots_in[end]

    C = collocation_matrix(B, xcol)

    @testset "Spline (k = $k)" begin
        @testset "Polynomial" begin
            test_polynomial(xcol, BSplineOrder(k))
        end

        # Generate data at collocation points and get B-spline coefficients.
        ucol = cos.(xcol)
        coefs = C \ ucol

        @inferred Spline(B, coefs)
        S = Spline(B, coefs)
        @test length(S) == length(B)
        @test all(S.(xcol) .≈ ucol)
        @test coefficients(S) === coefs
        @test diff(S, Derivative(0)) === S
        @test_nowarn show(devnull, S)

        # Create new spline, then compare it to S.
        let P = Spline(undef, B)
            cp = coefficients(P)
            fill!(cp, 0)
            @test P != S
            @test !(P ≈ S)

            copy!(cp, coefs)  # copy coefficients of S
            @test P == S
            @test P ≈ S
        end
    end

    nothing
end

function test_splines(::BSplineOrder{k}) where {k}
    knots_in = gauss_lobatto_points(10 + k)

    @inferred BSplineBasis(BSplineOrder(k), knots_in)
    @inferred (() -> BSplineBasis(k, knots_in))()

    g = BSplineBasis(k, knots_in)
    @test order(g) == k
    test_splines(g, knots_in)

    nothing
end

@testset "Splines" begin
    test_splines(BSplineOrder(4))
    test_splines(BSplineOrder(5))
end
