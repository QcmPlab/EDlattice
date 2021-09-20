module ED_MAIN
  USE SF_IOTOOLS, only: str,reg
  USE SF_TIMER,only: start_timer,stop_timer
  USE ED_INPUT_VARS
  USE ED_VARS_GLOBAL
  USE ED_EIGENSPACE, only: state_list,es_delete_espace
  USE ED_AUX_FUNX
  USE ED_SETUP
  USE ED_HAMILTONIAN
  USE ED_GREENS_FUNCTIONS
  USE ED_OBSERVABLES
  USE ED_DIAG

  implicit none
  private
  !
  !>INIT ED SOLVER
  !
  interface ed_init_solver
     module procedure :: ed_init_solver_single
#ifdef _MPI
     module procedure :: ed_init_solver_single_mpi
#endif
  end interface ed_init_solver
  !>
  public :: ed_init_solver


  !
  !> ED SOLVER
  !
  interface ed_solve
     module procedure :: ed_solve_single
#ifdef _MPI
     module procedure :: ed_solve_single_mpi
#endif
  end interface ed_solve
  !>
  public :: ed_solve

  character(len=64)                                  :: suffix



contains





  !+-----------------------------------------------------------------------------+!
  ! PURPOSE: allocate Memory and Initialize ED -+!
  !+-----------------------------------------------------------------------------+!
  subroutine ed_init_solver_single()
    write(LOGfile,"(A)")"INIT ED SOLVER"
    !
    !Init ED Structure & memory
    call init_ed_structure()
    !
    !Check Hmatrix is allocated:
    if(.not.Hmatrix%status)stop "ED_INIT_SOLVER ERROR: Hmatrix is not allocated"
    !
    call setup_global
    !
  end subroutine ed_init_solver_single

#ifdef _MPI
  subroutine ed_init_solver_single_mpi(MpiComm)
    integer :: MpiComm
    !
    !SET THE LOCAL MPI COMMUNICATOR :
    call ed_set_MpiComm(MpiComm)
    !
    write(LOGfile,"(A)")"INIT ED SOLVER"
    !
    !Init ED Structure & memory
    call init_ed_structure()
    !
    !Check Hmatrix is allocated:
    if(.not.Hmatrix%status)stop "ED_INIT_SOLVER ERROR: Hmatrix is not allocated"
    !
    call setup_global
    !
    call ed_del_MpiComm()
    !
  end subroutine ed_init_solver_single_mpi
#endif


  !+-----------------------------------------------------------------------------+!
  !PURPOSE: solve the impurity problems for a single or many independent
  ! lattice site using ED. 
  !+-----------------------------------------------------------------------------+!
  subroutine ed_solve_single(sflag)
    logical,optional                :: sflag
    logical                         :: check,iflag
    !
    iflag=.true. ;if(present(sflag))iflag=sflag
    !
    if(MpiMaster)call save_input_file(str(ed_input_file))
    !
    if(.not.Hmatrix%status)stop "ED_INIT_SOLVER ERROR: Hmatrix is not allocated"
    call Hij_write(unit=LOGfile)
    !
    !
    !SOLVE THE QUANTUM IMPURITY PROBLEM:
    call diagonalize_impurity()         !find target states by digonalization of Hamiltonian
    if(iflag)then
       call buildgf_impurity()             !build the one-particle impurity Green's functions  & Self-energy
       call buildchi_impurity()            !build the local susceptibilities (spin [todo charge])
    endif
    call observables_impurity()         !obtain impurity observables as thermal averages.          
    call local_energy_impurity()        !obtain the local energy of the effective impurity problem
    !
    call es_delete_espace(state_list)
    nullify(spHtimesV_p)
    return
  end subroutine ed_solve_single



#ifdef _MPI
  subroutine ed_solve_single_mpi(MpiComm,sflag)
    integer                         :: MpiComm
    logical,optional                :: sflag
    logical                         :: check,iflag
    !
    iflag=.true. ;if(present(sflag))iflag=sflag
    !
    !SET THE LOCAL MPI COMMUNICATOR :
    call ed_set_MpiComm(MpiComm)
    !
    if(MpiMaster)call save_input_file(str(ed_input_file))
    !
    if(.not.Hmatrix%status)stop "ED_INIT_SOLVER ERROR: Hmatrix is not allocated"
    call Hij_write(unit=LOGfile)
    !
    !SOLVE THE QUANTUM IMPURITY PROBLEM:
    call diagonalize_impurity()         !find target states by digonalization of Hamiltonian
    if(iflag)then
       call buildgf_impurity()             !build the one-particle impurity Green's functions  & Self-energy
       call buildchi_impurity() !build the local susceptibilities (spin [todo charge])
    endif
    call observables_impurity()         !obtain impurity observables as thermal averages.
    call local_energy_impurity()        !obtain the local energy of the effective impurity problem
    !
    call es_delete_espace(state_list)
    !
    !DELETE THE LOCAL MPI COMMUNICATOR:
    call ed_del_MpiComm()
    nullify(spHtimesV_p)
  end subroutine ed_solve_single_mpi
#endif

end module ED_MAIN






