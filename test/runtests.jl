using StartUpDG
using Test
using LinearAlgebra

@testset "Other utils" begin
    tol = 5e2*eps()

    @test eye(4)≈I

    EToV,VX,VY = readGmsh2D("squareCylinder2D.msh")
    @test size(EToV)==(3031,3)

    using StartUpDG.ExplicitTimestepUtils
    a = ntuple(x->randn(2,3),3)
    b = ntuple(x->randn(2,3),3)
    bcopy!.(a,b)
    @test a==b

    # feed zero rhs to PI controller = max timestep, errEst = 0
    rka,rkE,rkc = dp56()
    PI = init_PI_controller(5)
    Q = (randn(2,4),randn(2,4))
    rhsQrk = ntuple(x->zero.(Q),length(rkE))
    accept_step, dt_new, errEst =
        compute_adaptive_dt(Q,rhsQrk,1.0,rkE,PI)
    @test accept_step == true
    @test dt_new == PI.dtmax
    @test abs(errEst) < tol
end

# some code not tested to avoid redundancy from tests in NodesAndModes.
@testset "Reference elements" begin
    tol = 5e2*eps()

    N = 2

    #####
    ##### interval
    #####
    rd = init_reference_interval(N)
    @test abs(sum(rd.rq.*rd.wq)) < tol
    @test rd.nrJ ≈ [-1,1]
    @test rd.Pq*rd.Vq ≈ I

    #####
    ##### triangles
    #####
    rd = init_reference_tri(N)
    @test abs(sum(rd.wq)) ≈ 2
    @test abs(sum(rd.wf)) ≈ 6
    @test abs(sum(rd.wf .* rd.nrJ)) + abs(sum(rd.wf .* rd.nsJ)) < tol
    @test rd.Pq*rd.Vq ≈ I

    #####
    ##### quads
    #####
    rd = init_reference_quad(N)
    @test abs(sum(rd.wq)) ≈ 4
    @test abs(sum(rd.wf)) ≈ 8
    @test abs(sum(rd.wf .* rd.nrJ)) + abs(sum(rd.wf .* rd.nsJ)) < tol
    @test rd.Pq*rd.Vq ≈ I

    #####
    ##### hexes
    #####
    rd = init_reference_hex(N)
    @test abs(sum(rd.wq)) ≈ 8
    @test abs(sum(rd.wf)) ≈ 6*4
    @test abs(sum(rd.wf .* rd.nrJ)) < tol
    @test abs(sum(rd.wf .* rd.nsJ)) < tol
    @test abs(sum(rd.wf .* rd.ntJ)) < tol
    @test rd.Pq*rd.Vq ≈ I
end

@testset "1D mesh initialization" begin
    tol = 5e2*eps()

    N = 3
    K1D = 2
    rd = init_reference_interval(N)
    VX,EToV = uniform_1D_mesh(K1D)
    md = init_DG_mesh(VX,EToV,rd)
    @unpack wq,Dr,Vq,Vf,wf = rd
    @unpack Nfaces = rd
    @unpack x,xq,xf,K = md
    @unpack rxJ,J,nxJ,wJq = md
    @unpack mapM,mapP,mapB = md

    # check positivity of Jacobian
    @test all(J .> 0)

    # check differentiation
    u = @. x^2 + 2*x
    dudx_exact = @. 2*x + 2
    dudr = Dr*u
    dudx = (rxJ.*dudr)./J
    @test dudx ≈ dudx_exact

    # check volume integration
    @test Vq*x ≈ xq
    @test diagm(wq)*(Vq*J) ≈ wJq
    @test abs(sum(xq.*wJq)) < tol

    # check surface integration
    @test Vf*x ≈ xf
    @test abs(sum(nxJ)) < tol

    # check connectivity and boundary maps
    u = @. (1-x)*(1+x)
    uf = Vf*u
    @test uf ≈ uf[mapP]
    @test norm(uf[mapB]) < tol

    # check periodic node connectivity maps
    LX = 2
    build_periodic_boundary_maps!(md,rd,LX)
    @unpack mapP = md
    u = @. sin(pi*(.5+x))
    uf = Vf*u
    @test uf ≈ uf[mapP]
end

@testset "2D tri mesh initialization" begin
    tol = 5e2*eps()

    N = 3
    K1D = 2
    rd = init_reference_tri(N)
    VX,VY,EToV = uniform_tri_mesh(K1D)
    md = init_DG_mesh(VX,VY,EToV,rd)
    @unpack wq,Dr,Ds,Vq,Vf,wf = rd
    Nfaces = length(rd.fv)
    @unpack x,y,xq,yq,xf,yf,K = md
    @unpack rxJ,sxJ,ryJ,syJ,J,nxJ,nyJ,sJ,wJq = md
    @unpack FToF,mapM,mapP,mapB = md

    # check positivity of Jacobian
    # @show J[1,:]
    @test all(J .> 0)

    # check differentiation
    u = @. x^2 + 2*x*y - y^2
    dudx_exact = @. 2*x + 2*y
    dudy_exact = @. 2*x - 2*y
    dudr,duds = (D->D*u).((Dr,Ds))
    dudx = (rxJ.*dudr + sxJ.*duds)./J
    dudy = (ryJ.*dudr + syJ.*duds)./J
    @test dudx ≈ dudx_exact
    @test dudy ≈ dudy_exact

    # check volume integration
    @test Vq*x ≈ xq
    @test Vq*y ≈ yq
    @test diagm(wq)*(Vq*J) ≈ wJq
    @test abs(sum(xq.*wJq)) < tol
    @test abs(sum(yq.*wJq)) < tol

    # check surface integration
    @test Vf*x ≈ xf
    @test Vf*y ≈ yf
    @test abs(sum(wf.*nxJ)) < tol
    @test abs(sum(wf.*nyJ)) < tol
    @test sum(@. wf*nxJ*(1+xf)/2) ≈ 2.0 # check sign of normals

    # check connectivity and boundary maps
    u = @. (1-x)*(1+x)*(1-y)*(1+y)
    uf = Vf*u
    @test uf ≈ uf[mapP]
    @test norm(uf[mapB]) < tol

    # check periodic node connectivity maps
    LX,LY = 2,2
    build_periodic_boundary_maps!(md,rd,LX,LY)
    @unpack mapP = md
    #mapPB = build_periodic_boundary_maps(xf,yf,LX,LY,Nfaces*K,mapM,mapP,mapB)
    #mapP[mapB] = mapPB
    u = @. sin(pi*(.5+x))*sin(pi*(.5+y))
    uf = Vf*u
    @test uf ≈ uf[mapP]
end

@testset "2D quad mesh initialization" begin
    tol = 5e2*eps()

    N = 3
    K1D = 2
    rd = init_reference_quad(N)
    VX,VY,EToV = uniform_quad_mesh(K1D)
    md = init_DG_mesh(VX,VY,EToV,rd)
    @unpack wq,Dr,Ds,Vq,Vf,wf = rd
    Nfaces = length(rd.fv)
    @unpack x,y,xq,yq,xf,yf,K = md
    @unpack rxJ,sxJ,ryJ,syJ,J,nxJ,nyJ,sJ,wJq = md
    @unpack FToF,mapM,mapP,mapB = md

    # check positivity of Jacobian
    @test all(J .> 0)

    # check differentiation
    u = @. x^2 + 2*x*y - y^2
    dudx_exact = @. 2*x + 2*y
    dudy_exact = @. 2*x - 2*y
    dudr,duds = (D->D*u).((Dr,Ds))
    dudx = (rxJ.*dudr + sxJ.*duds)./J
    dudy = (ryJ.*dudr + syJ.*duds)./J
    @test dudx ≈ dudx_exact
    @test dudy ≈ dudy_exact

    # check volume integration
    @test Vq*x ≈ xq
    @test Vq*y ≈ yq
    @test diagm(wq)*(Vq*J) ≈ wJq
    @test abs(sum(xq.*wJq)) < tol
    @test abs(sum(yq.*wJq)) < tol

    # check surface integration
    @test Vf*x ≈ xf
    @test Vf*y ≈ yf
    @test abs(sum(diagm(wf)*nxJ)) < tol
    @test abs(sum(diagm(wf)*nyJ)) < tol
    @test sum(@. wf*nxJ*(1+xf)/2) ≈ 2.0 # check sign of normals

    # check connectivity and boundary maps
    u = @. (1-x)*(1+x)*(1-y)*(1+y)
    uf = Vf*u
    @test uf ≈ uf[mapP]
    @test norm(uf[mapB]) < tol

    # check periodic node connectivity maps
    LX,LY = 2,2
    build_periodic_boundary_maps!(md,rd,LX,LY)
    @unpack mapP = md
    u = @. sin(pi*(.5+x))*sin(pi*(.5+y))
    uf = Vf*u
    @test uf ≈ uf[mapP]
end

@testset "3D hex mesh initialization" begin
    tol = 5e2*eps()

    N = 2
    K1D = 2
    init_ref_elem = [init_reference_hex]
    unif_mesh = [uniform_hex_mesh]
    for (init_ref_elem,unif_mesh) in zip(init_ref_elem,unif_mesh)
        rd = init_ref_elem(N)
        VX,VY,VZ,EToV = unif_mesh(K1D)
        md = init_DG_mesh(VX,VY,VZ,EToV,rd)
        @unpack wq,Dr,Ds,Dt,Vq,Vf,wf = rd
        Nfaces = length(rd.fv)
        @unpack x,y,z,xq,yq,zq,wJq,xf,yf,zf,K = md
        @unpack rxJ,sxJ,txJ,ryJ,syJ,tyJ,rzJ,szJ,tzJ,J = md
        @unpack nxJ,nyJ,nzJ,sJ = md
        @unpack FToF,mapM,mapP,mapB = md

        # check positivity of Jacobian
        # @show J[1,:]
        @test all(J .> 0)

        # check differentiation
        u = @. x^2 + 2*x*y - y^2 + x*y*z
        dudx_exact = @. 2*x + 2*y + y*z
        dudy_exact = @. 2*x - 2*y + x*z
        dudz_exact = @. x*y
        dudr,duds,dudt = (D->D*u).((Dr,Ds,Dt))
        dudx = (rxJ.*dudr + sxJ.*duds + txJ.*dudt)./J
        dudy = (ryJ.*dudr + syJ.*duds + tyJ.*dudt)./J
        dudz = (rzJ.*dudr + szJ.*duds + tzJ.*dudt)./J
        @test dudx ≈ dudx_exact
        @test dudy ≈ dudy_exact
        @test dudz ≈ dudz_exact

        # check volume integration
        @test Vq*x ≈ xq
        @test Vq*y ≈ yq
        @test Vq*z ≈ zq
        @test diagm(wq)*(Vq*J) ≈ wJq
        @test abs(sum(xq.*wJq)) < tol
        @test abs(sum(yq.*wJq)) < tol
        @test abs(sum(zq.*wJq)) < tol

        # check surface integration
        @test Vf*x ≈ xf
        @test Vf*y ≈ yf
        @test Vf*z ≈ zf
        @test abs(sum(diagm(wf)*nxJ)) < tol
        @test abs(sum(diagm(wf)*nyJ)) < tol
        @test abs(sum(diagm(wf)*nzJ)) < tol

        # check connectivity and boundary maps
        u = @. (1-x)*(1+x)*(1-y)*(1+y)*(1-z)*(1+z)
        uf = Vf*u
        @test uf ≈ uf[mapP]
        @test norm(uf[mapB]) < tol

        # check periodic node connectivity maps
        LX,LY,LZ = 2,2,2
        build_periodic_boundary_maps!(md,rd,LX,LY,LZ)
        @unpack mapP = md
        u = @. sin(pi*(.5+x))*sin(pi*(.5+y))*sin(pi*(.5+z))
        uf = Vf*u
        @test uf ≈ uf[mapP]
    end
end
