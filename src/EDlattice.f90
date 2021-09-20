MODULE EDIPACK
  USE ED_INPUT_VARS, only: &
       ed_read_input , &
       Nsites        , &
       Norb          , &
       Nspin         , &
       Uloc          , &
       Ust           , &
       Jh            , &
       Jx            , &
       Jp            , &
       xmu           , &
       beta          , &
       eps           , &
       wini          , &
       wfin          , &
       sb_field      , &
       nread         , &
       nerr          , &
       Lmats         , &
       Lreal         , &
       Hfile         , &
       LOGfile   

  USE ED_GRAPH_MATRIX, only: &
       ed_Hij_info     => Hij_info     , &
       ed_Hij_add_link => Hij_add_link , &
       ed_Hij_read     => Hij_read     , &
       ed_Hij_get      => Hij_get      , &
       ed_Hij_local    => Hij_local    , &
       ed_Hij_write    => Hij_write

  USE ED_AUX_FUNX, only: ed_search_variable

  USE ED_IO, only: &
       ed_get_sigma_matsubara , &
       ed_get_sigma_realaxis  , &
       ed_get_gimp_matsubara  , &
       ed_get_gimp_realaxis   , &
       ed_get_dens            , &
       ed_get_mag             , &
       ed_get_docc            , &
       ed_get_elocal          , &
       ed_get_doubles         , &
       ed_get_density_matrix


  USE ED_MAIN, only: &
       ed_init_solver , &
       ed_solve


END MODULE EDIPACK
