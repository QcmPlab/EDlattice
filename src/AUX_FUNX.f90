MODULE ED_AUX_FUNX
  USE ED_INPUT_VARS
  USE ED_VARS_GLOBAL
  USE SF_TIMER
  USE SF_LINALG
  USE SF_MISC, only: assert_shape
  USE SF_IOTOOLS, only:free_unit,reg,txtfy
  USE SF_ARRAYS,  only: arange,linspace
  implicit none
  private

  !PACK lattice-orbital-spin INDICES into a single one
  public :: pack_indices
  !FERMIONIC OPERATORS IN BITWISE OPERATIONS
  public :: c,cdg
  !BIT DECOMPOSITION 
  public :: bdecomp
  !BINARY SEARCH
  public :: binary_search
  !MPI PROCEDURES
#ifdef _MPI
  public :: scatter_vector_MPI
  public :: scatter_basis_MPI
  public :: gather_vector_MPI
  public :: allgather_vector_MPI
#endif
  !
  !SEARCH CHEMICAL POTENTIAL, this should go into DMFT_TOOLS I GUESS
  public :: ed_search_variable
  !ALLOCATE/DEALLOCATE GRIDS
  public :: allocate_grids
  public :: deallocate_grids


contains


  function pack_indices(siteI,orbI,spinI) result(Indx)
    integer,intent(in)          :: siteI,orbI
    integer,intent(in),optional :: spinI
    integer                     :: Indx
    select case(orbI)
    case(1)
       Indx = siteI
    case default
       Indx = siteI + (orbI-1)*Nsites(orbI-1)
    end select
    if(present(spinI))Indx = Indx  + (spinI-1)*Ns
  end function pack_indices



  !##################################################################
  !##################################################################
  !CREATION / DESTRUCTION OPERATORS
  !##################################################################
  !##################################################################
  !+-------------------------------------------------------------------+
  !PURPOSE: input state |in> of the basis and calculates 
  !   |out>=C_pos|in>  OR  |out>=C^+_pos|in> ; 
  !   the sign of |out> has the phase convention, pos labels the sites
  !+-------------------------------------------------------------------+
  subroutine c(pos,in,out,fsgn)
    integer,intent(in)    :: pos
    integer,intent(in)    :: in
    integer,intent(inout) :: out
    real(8),intent(inout) :: fsgn    
    integer               :: l
    if(.not.btest(in,pos-1))stop "C error: C_i|...0_i...>"
    fsgn=1d0
    do l=1,pos-1
       if(btest(in,l-1))fsgn=-fsgn
    enddo
    out = ibclr(in,pos-1)
  end subroutine c

  subroutine cdg(pos,in,out,fsgn)
    integer,intent(in)    :: pos
    integer,intent(in)    :: in
    integer,intent(inout) :: out
    real(8),intent(inout) :: fsgn    
    integer               :: l
    if(btest(in,pos-1))stop "C^+ error: C^+_i|...1_i...>"
    fsgn=1d0
    do l=1,pos-1
       if(btest(in,l-1))fsgn=-fsgn
    enddo
    out = ibset(in,pos-1)
  end subroutine cdg





  !##################################################################
  !##################################################################
  !               BITWISE OPERATIONS
  !##################################################################
  !##################################################################
  !+------------------------------------------------------------------+
  !PURPOSE  : input a state |i> and output a vector ivec(Nlevels)
  !with its binary decomposition
  !(corresponds to the decomposition of the number i-1)
  !+------------------------------------------------------------------+
  function bdecomp(i,Ntot) result(ivec)
    integer :: Ntot,ivec(Ntot),l,i
    logical :: busy
    !this is the configuration vector |1,..,Ns,Ns+1,...,Ntot>
    !obtained from binary decomposition of the state/number i\in 2^Ntot
    do l=0,Ntot-1
       busy=btest(i,l)
       ivec(l+1)=0
       if(busy)ivec(l+1)=1
    enddo
  end function bdecomp



  !+------------------------------------------------------------------+
  !PURPOSE : binary search of a value in an array
  !+------------------------------------------------------------------+
  recursive function binary_search(a,value) result(bsresult)
    integer,intent(in) :: a(:), value
    integer            :: bsresult, mid
    mid = size(a)/2 + 1
    if (size(a) == 0) then
       bsresult = 0        ! not found
       !stop "binary_search error: value not found"
    else if (a(mid) > value) then
       bsresult= binary_search(a(:mid-1), value)
    else if (a(mid) < value) then
       bsresult = binary_search(a(mid+1:), value)
       if (bsresult /= 0) then
          bsresult = mid + bsresult
       end if
    else
       bsresult = mid      ! SUCCESS!!
    end if
  end function binary_search





  !##################################################################
  !##################################################################
  !AUXILIARY COMPUTATIONAL ROUTINES ARE HERE BELOW:
  !##################################################################
  !##################################################################

#ifdef _MPI
  !! Scatter V into the arrays Vloc on each thread: sum_threads(size(Vloc)) must be equal to size(v)
  subroutine scatter_vector_MPI(MpiComm,v,vloc)
    integer                          :: MpiComm
    real(8),dimension(:)             :: v    !size[N]
    real(8),dimension(:)             :: vloc !size[Nloc]
    integer                          :: i,irank,Nloc,N
    integer                          :: v_start,v_end,vloc_start,vloc_end
    integer,dimension(:),allocatable :: Counts,Offset
    integer                          :: MpiSize,MpiIerr
    logical                          :: MpiMaster
    !
    if( MpiComm == MPI_UNDEFINED .OR. MpiComm == Mpi_Comm_Null )return
    ! stop "scatter_vector_MPI error: MpiComm == MPI_UNDEFINED"
    !
    MpiSize   = get_size_MPI(MpiComm)
    MpiMaster = get_master_MPI(MpiComm)
    !
    Nloc = size(Vloc)
    N = 0
    call AllReduce_MPI(MpiComm,Nloc,N)
    if(MpiMaster.AND.N /= size(V)) stop "scatter_vector_MPI error: size(V) != Mpi_Allreduce(Nloc)"
    !
    allocate(Counts(0:MpiSize-1)) ; Counts=0
    allocate(Offset(0:MpiSize-1)) ; Offset=0
    !
    !Get Counts;
    call MPI_AllGather(Nloc,1,MPI_INTEGER,Counts,1,MPI_INTEGER,MpiComm,MpiIerr)
    !
    !Get Offset:
    Offset(0)=0
    do i=1,MpiSize-1
       Offset(i) = Offset(i-1) + Counts(i-1)
    enddo
    !
    Vloc=0d0
    v_start = 1
    v_end   = 1 ; if(MpiMaster)v_end = N
    vloc_start = 1
    vloc_end   = Nloc
    call MPI_Scatterv(V(v_start:v_end),Counts,Offset,MPI_DOUBLE_PRECISION,&
         Vloc(vloc_start:vloc_end),Nloc,MPI_DOUBLE_PRECISION,0,MpiComm,MpiIerr)
    !
    return
  end subroutine scatter_vector_MPI


  subroutine scatter_basis_MPI(MpiComm,v,vloc)
    integer                :: MpiComm
    real(8),dimension(:,:) :: v    !size[N,N]
    real(8),dimension(:,:) :: vloc !size[Nloc,Neigen]
    integer                :: N,Nloc,Neigen,i
    N      = size(v,1)
    Nloc   = size(vloc,1)
    Neigen = size(vloc,2)
    if( size(v,2) < Neigen ) stop "error scatter_basis_MPI: size(v,2) < Neigen"
    !
    do i=1,Neigen
       call scatter_vector_MPI(MpiComm,v(:,i),vloc(:,i))
    end do
    !
    return
  end subroutine scatter_basis_MPI


  !! AllGather Vloc on each thread into the array V: sum_threads(size(Vloc)) must be equal to size(v)
  subroutine gather_vector_MPI(MpiComm,vloc,v)
    integer                          :: MpiComm
    real(8),dimension(:)             :: vloc !size[Nloc]
    real(8),dimension(:)             :: v    !size[N]
    integer                          :: i,irank,Nloc,N
    integer                          :: v_start,v_end,vloc_start,vloc_end
    integer,dimension(:),allocatable :: Counts,Offset
    integer                          :: MpiSize,MpiIerr
    logical                          :: MpiMaster
    !
    if(  MpiComm == MPI_UNDEFINED .OR. MpiComm == Mpi_Comm_Null ) return
    !stop "gather_vector_MPI error: MpiComm == MPI_UNDEFINED"
    !
    MpiSize   = get_size_MPI(MpiComm)
    MpiMaster = get_master_MPI(MpiComm)
    !
    Nloc = size(Vloc)
    N = 0
    call AllReduce_MPI(MpiComm,Nloc,N)
    if(MpiMaster.AND.N /= size(V)) stop "gather_vector_MPI error: size(V) != Mpi_Allreduce(Nloc)"
    !
    allocate(Counts(0:MpiSize-1)) ; Counts=0
    allocate(Offset(0:MpiSize-1)) ; Offset=0
    !
    !Get Counts;
    call MPI_AllGather(Nloc,1,MPI_INTEGER,Counts,1,MPI_INTEGER,MpiComm,MpiIerr)
    !
    !Get Offset:
    Offset(0)=0
    do i=1,MpiSize-1
       Offset(i) = Offset(i-1) + Counts(i-1)
    enddo
    !
    v_start = 1
    v_end   = 1 ; if(MpiMaster)v_end = N
    vloc_start = 1
    vloc_end   = Nloc
    call MPI_Gatherv(Vloc(vloc_start:vloc_end),Nloc,MPI_DOUBLE_PRECISION,&
         V(v_start:v_end),Counts,Offset,MPI_DOUBLE_PRECISION,0,MpiComm,MpiIerr)
    !
    return
  end subroutine gather_vector_MPI


  !! AllGather Vloc on each thread into the array V: sum_threads(size(Vloc)) must be equal to size(v)
  subroutine allgather_vector_MPI(MpiComm,vloc,v)
    integer                          :: MpiComm
    real(8),dimension(:)             :: vloc !size[Nloc]
    real(8),dimension(:)             :: v    !size[N]
    integer                          :: i,iph,irank,Nloc,N
    integer                          :: v_start,v_end,vloc_start,vloc_end
    integer,dimension(:),allocatable :: Counts,Offset
    integer                          :: MpiSize,MpiIerr
    logical                          :: MpiMaster
    !
    if(  MpiComm == MPI_UNDEFINED .OR. MpiComm == Mpi_Comm_Null ) return
    ! stop "gather_vector_MPI error: MpiComm == MPI_UNDEFINED"
    !
    MpiSize   = get_size_MPI(MpiComm)
    MpiMaster = get_master_MPI(MpiComm)
    !
    Nloc = size(Vloc)
    N    = 0
    call AllReduce_MPI(MpiComm,Nloc,N)
    if(MpiMaster.AND.N /= size(V)) stop "allgather_vector_MPI error: size(V) != Mpi_Allreduce(Nloc)"
    !
    allocate(Counts(0:MpiSize-1)) ; Counts=0
    allocate(Offset(0:MpiSize-1)) ; Offset=0
    !
    !Get Counts;
    call MPI_AllGather(Nloc,1,MPI_INTEGER,Counts,1,MPI_INTEGER,MpiComm,MpiIerr)
    !
    !Get Offset:
    Offset(0)=0
    do i=1,MpiSize-1
       Offset(i) = Offset(i-1) + Counts(i-1)
    enddo
    !
    V = 0d0
    v_start = 1
    v_end   = N
    vloc_start = 1
    vloc_end   = Nloc
    call MPI_AllGatherv(Vloc(vloc_start:vloc_end),Nloc,MPI_DOUBLE_PRECISION,&
         V(v_start:v_end),Counts,Offset,MPI_DOUBLE_PRECISION,MpiComm,MpiIerr)
    !
    return
  end subroutine Allgather_vector_MPI
#endif







  !+------------------------------------------------------------------+
  !PURPOSE  : Allocate arrays and setup frequencies and times
  !+------------------------------------------------------------------+
  subroutine allocate_grids
    integer :: i
    if(.not.allocated(wm))allocate(wm(Lmats))
    if(.not.allocated(vm))allocate(vm(0:Lmats))          !bosonic frequencies
    if(.not.allocated(wr))allocate(wr(Lreal))
    if(.not.allocated(vr))allocate(vr(Lreal))
    if(.not.allocated(tau))allocate(tau(0:Ltau))
    wm     = pi/beta*real(2*arange(1,Lmats)-1,8)
    do i=0,Lmats
       vm(i) = pi/beta*2*i
    enddo
    wr     = linspace(wini,wfin,Lreal)
    vr     = linspace(0d0,wfin,Lreal)
    tau(0:)= linspace(0d0,beta,Ltau+1)
  end subroutine allocate_grids


  subroutine deallocate_grids
    if(allocated(wm))deallocate(wm)
    if(allocated(vm))deallocate(vm)
    if(allocated(tau))deallocate(tau)
    if(allocated(wr))deallocate(wr)
    if(allocated(vr))deallocate(vr)
  end subroutine deallocate_grids










  !##################################################################
  !##################################################################
  ! ROUTINES TO SEARCH CHEMICAL POTENTIAL UP TO SOME ACCURACY
  ! can be used to fix any other *var so that  *ntmp == nread
  !##################################################################
  !##################################################################

  !+------------------------------------------------------------------+
  !PURPOSE  : 
  !+------------------------------------------------------------------+
  subroutine ed_search_variable(var,ntmp,converged)
    real(8),intent(inout) :: var
    real(8),intent(in)    :: ntmp
    logical,intent(inout) :: converged
    logical               :: bool
    real(8),save          :: chich
    real(8),save          :: nold
    real(8),save          :: var_new
    real(8),save          :: var_old
    real(8)               :: var_sign
    real(8)               :: delta_n,delta_v,chi_shift
    !
    real(8)               :: ndiff
    integer,save          :: count=0,totcount=0,i
    integer               :: unit
    !
    !check actual value of the density *ntmp* with respect to goal value *nread*
    count=count+1
    totcount=totcount+1
    !  
    if(count==1)then
       chich = ndelta        !~0.2
       inquire(file="var_compressibility.restart",EXIST=bool)
       if(bool)then
          write(LOGfile,"(A)")"Reading compressibility from file"
          open(free_unit(unit),file="var_compressibility.restart")
          read(unit,*)chich
          close(unit)
       endif
       var_old = var
    endif
    !
    ndiff=ntmp-nread
    !
    open(free_unit(unit),file="var_compressibility.used")
    write(unit,*)chich
    close(unit)
    !
    ! if(abs(ndiff)>nerr)then
    !Get 'charge compressibility"
    delta_n = ntmp-nold
    delta_v = var-var_old
    if(count>1)chich = delta_v/(delta_n+1d-10) !1d-4*nerr)  !((ntmp-nold)/(var-var_old))**-1
    !
    !Add here controls on chich: not to be too small....
    if(chich>10d0)chich=2d0*chich/abs(chich) !do nothing?
    !
    chi_shift = ndiff*chich
    !
    !update chemical potential
    var_new = var - chi_shift
    !
    !
    !re-define variables:
    nold    = ntmp
    var_old = var
    var     = var_new
    !
    !Print information
    write(LOGfile,"(A11,F16.9,A,F15.9)")  "n      = ",ntmp,"| instead of",nread
    write(LOGfile,"(A11,ES16.9,A,ES16.9)")"n_diff = ",ndiff,"/",nerr
    write(LOGfile,"(A11,ES16.9,A,ES16.9)")"dv     = ",delta_v
    write(LOGfile,"(A11,ES16.9,A,ES16.9)")"dn     = ",delta_n
    write(LOGfile,"(A11,F16.9,A,F15.9)")  "dv/dn  = ",chich
    var_sign = (var-var_old)/abs(var-var_old)
    if(var_sign>0d0)then
       write(LOGfile,"(A11,ES16.9,A4)")"shift    = ",chi_shift," ==>"
    else
       write(LOGfile,"(A11,ES16.9,A4)")"shift    = ",chi_shift," <=="
    end if
    write(LOGfile,"(A11,F16.9)")"var     = ",var
    !
    ! else
    !    count=0
    ! endif


    !Save info about search variable iteration:
    open(free_unit(unit),file="search_variable_iteration_info.ed",position="append")
    ! if(count==1)write(unit,*)"#var,ntmp,ndiff"
    write(unit,*)totcount,var,ntmp,ndiff
    close(unit)
    !
    !If density is not converged set convergence to .false.
    if(abs(ndiff)>nerr)converged=.false.
    !
    write(LOGfile,"(A18,I5)")"Search var count= ",count
    write(LOGfile,"(A19,L2)")"Converged       = ",converged
    print*,""
    !
    open(free_unit(unit),file="var_compressibility.restart")
    write(unit,*)chich
    close(unit)
    !
  end subroutine ed_search_variable













END MODULE ED_AUX_FUNX