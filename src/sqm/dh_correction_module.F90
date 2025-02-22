#include "dprec.fh"
module dh_correction_module
! ----------------------------------------------------------------------
! PURPOSE: Dispersion and hydrogen bond correction for semiempirical
!          methods
!
! References: 
! D+ correction: Korth, JCTC 6 (2010) 3808-3816.
! This is based on the dispersion correction as described in
! Jurecka et al., JCC 28 (2007) 555-569.
! eqs (1), (3), (4) and (5).
! Parameters for the dispersion correction, however, have been
! reoptimized, see
! Korth et al., JCTC 6 (2010) 344-352.
!
! 
! Author: Andreas W. Goetz <agoetz@sdsc.edu>
!         Kyoyeon Park <kypark@ucsd.edu>
! Date  : June-August 2011
!
! TODO
! ----------------------------------------------------------------------
  
  implicit none

  private
  public :: dh_correction
  public :: dh_correction_grad
  public :: dh_correction_info

contains


  ! Calculate dispersion and hydrogen bond correction
  subroutine dh_correction(qm2_params,qm2_struct, natom, coord, atomic_numbers, qmtheory, &
                           dCorrEner,hCorrEner)

    use qm2_params_module,  only : qm2_params_type
    use qmmm_qmtheorymodule, only : qmTheoryType
    use qmmm_module, only              : qm2_structure
    implicit none

    type(qm2_params_type),intent(inout) :: qm2_params
    type(qm2_structure),intent(inout) :: qm2_struct
    integer, intent(in) :: natom
    _REAL_, intent(in) :: coord(3,natom)
    integer, intent(in) :: atomic_numbers(natom)
    type(qmTheoryType), intent(in) :: qmtheory

    _REAL_, intent(out) :: dCorrEner, hCorrEner

    _REAL_ :: xyz(3,natom)
    _REAL_ :: bo_matrix(natom,natom)
    logical :: debug = .false.

    if (debug) then
       write (6,'(a)') '>>>>> Entered dh_correction() (dh_correcton_module)'
       call flush(6)
    end if

    dCorrEner = 0.0d0
    hCorrEner = 0.0d0

    ! Calculate bond order matrix

    call calc_bo_matrix(qm2_params,qm2_struct,natom,bo_matrix)

    xyz(:,:)=coord(:,:)

    ! Calculate disersion corrections
    if (qmtheory%DISPERSION .or. qmtheory%DISPERSION_HYDROGENPLUS) then
       call calc_d_correction(natom,xyz,atomic_numbers,qmtheory, &
                              bo_matrix,dCorrEner)
    end if

    if (qmtheory%DISPERSION_HYDROGENPLUS) then
       call calc_h_correction(natom,xyz,atomic_numbers,qmtheory, &
                              bo_matrix,hCorrEner, debug)
    end if

    if (debug) then
       write(6,'(a,f25.8,a)')' Dispersion contribution = ',dCorrEner,' kcal/mol'

       if (qmtheory%DISPERSION_HYDROGENPLUS) then
          write(6,'(a,f25.8,a)')' H-bond contribution =     ',hCorrEner,' kcal/mol'
       endif
    end if

    if (debug) then
       write (6,'(a)') '<<<<< Leaving dh_correction()'
       call flush(6)
    end if

  end subroutine dh_correction


! Gradient of Dispersion and Hydrogen correction 

  subroutine dh_correction_grad(qm2_params, qm2_struct, natom, coord, atomic_numbers, qmtheory, dxyz)

    use qm2_params_module,  only : qm2_params_type
    use qmmm_qmtheorymodule, only : qmTheoryType
    use qmmm_module, only              : qm2_structure

    implicit none

    type(qm2_params_type),intent(inout) :: qm2_params
    type(qm2_structure),target :: qm2_struct
    integer, intent(in) :: natom
    _REAL_, intent(in) :: coord(3,natom)
    integer, intent(in) :: atomic_numbers(natom)
    _REAL_, intent(inout) :: dxyz(3,natom)
    type(qmTheoryType), intent(in) :: qmtheory

    _REAL_ :: bo_matrix(natom,natom)
    logical :: debug=.false.

    if (debug) then
       write (6,'(a)') '>>>>> Entered dh_correction_grad() (dh_correcton_module)'
       call flush(6)
    end if

    call calc_bo_matrix(qm2_params,qm2_struct,natom,bo_matrix)

    if (qmtheory%DISPERSION .or. qmtheory%DISPERSION_HYDROGENPLUS) then
       call calc_d_grad(natom,coord,atomic_numbers,qmtheory,bo_matrix,dxyz)
    endif

    if (qmtheory%DISPERSION_HYDROGENPLUS) then
       call calc_h_grad(natom,coord,atomic_numbers,qmtheory,bo_matrix,dxyz, debug)
    endif

    if (debug) then
       write (6,'(a)') '<<<<< Leaving dh_correction_grad()'
       call flush(6)
    end if

  end subroutine dh_correction_grad


! D gradient

  subroutine calc_d_grad(natom,coord,atomic_numbers,qmtheory,bo_matrix,dxyz)

    use qmmm_qmtheorymodule, only : qmTheoryType

    implicit none

    integer, intent(in) :: natom
    _REAL_, intent(in) :: coord(3,natom)
    integer, intent(in) :: atomic_numbers(natom)
    _REAL_, intent(inout) :: dxyz(3,natom)
    type(qmTheoryType), intent(in) :: qmtheory
    _REAL_, intent(in) :: bo_matrix(natom,natom)

    _REAL_ :: xyz(3,natom)
    _REAL_ :: grad(3)
    _REAL_ :: ener(2), fac
    _REAL_, parameter :: stepsize = 1.0d-5
    integer :: istep
    integer :: i, j



    do i=1,natom

       grad(:)=0.0d0
       ener(:)=0.0d0

       do j=1,3

          do istep=1,2

             fac=1.0d0

             if (istep .eq. 2) then
                fac=-1.0d0
             endif

             xyz(:,:)=coord(:,:)
             xyz(j,i) = coord(j,i)+fac*stepsize

             call calc_d_correction(natom,xyz,atomic_numbers,qmtheory, &
                               bo_matrix,ener(istep))

          enddo

          grad(j)=(ener(1)-ener(2))/(stepsize*2.0d0)

       enddo

       dxyz(1:3,i)=dxyz(1:3,i)+grad(1:3)

    enddo


  end subroutine calc_d_grad


! H gradient

  subroutine calc_h_grad(natom,coord,atomic_numbers,qmtheory,bo_matrix,dxyz,debug)

    use qmmm_qmtheorymodule, only : qmTheoryType

    implicit none

    integer, intent(in) :: natom
    _REAL_, intent(in) :: coord(3,natom)
    integer, intent(in) :: atomic_numbers(natom)
    _REAL_, intent(inout) :: dxyz(3,natom)
    type(qmTheoryType), intent(in) :: qmtheory
    _REAL_, intent(in) :: bo_matrix(natom,natom)
    logical, intent(in) :: debug

    _REAL_ :: xyz(3,natom)
    _REAL_ :: grad(3)
    _REAL_ :: ener(2), fac
    _REAL_, parameter :: stepsize = 1.0d-7
    integer :: istep
    integer :: i, j


    do i=1,natom

       grad(:)=0.0d0
       ener(:)=0.0d0

       do j=1,3

          do istep=1,2

             fac=1.0d0

             if (istep .eq. 2) then
                fac=-1.0d0
             endif

             xyz(:,:)=coord(:,:)
             xyz(j,i)=coord(j,i)+fac*stepsize

             call calc_h_correction(natom,xyz,atomic_numbers,qmtheory, &
                               bo_matrix,ener(istep), debug)

          enddo

          grad(j)=(ener(1)-ener(2))/(stepsize*2.0d0)

       enddo

       dxyz(1:3,i)=dxyz(1:3,i)+grad(1:3)

    enddo


  end subroutine calc_h_grad


! D correction
  subroutine calc_d_correction(natom,xyz,atomic_numbers,qmtheory, &
                               bo_matrix,dCorrEner)

    use qmmm_qmtheorymodule, only : qmTheoryType

    implicit none

    integer, intent(in) :: natom
    _REAL_, intent(in) :: xyz(3,natom)
    integer, intent(in) :: atomic_numbers(natom)
    type(qmTheoryType), intent(in) :: qmtheory

    _REAL_, intent(in) :: bo_matrix(natom,natom)
    _REAL_, intent(out) :: dCorrEner

    _REAL_ :: alpha, sr, s6
    _REAL_ :: c6, req
    _REAL_ :: corren
    _REAL_ :: vec(3), dum1, dum2
    _REAL_ :: dist, fdamp
    integer :: l_Csp3(natom), bond_count
    integer :: i, j, iatom, jatom

    _REAL_, parameter :: parCutCsp3 = 0.5d0
    _REAL_, parameter :: kjtokc = 0.23900573613766730401d0

    logical :: lDiffMols

    dCorrEner=0.0d0

    if (qmtheory%PM6) then
       alpha = 20.0d0 
       sr = 1.04d0
       s6 = 0.89d0
    else if (qmtheory%AM1) then
       alpha = 56.0d0
       sr = 0.91d0
       s6 = 1.18d0
    else
       call sander_bomb('calc_d_correction (dh_correction_module)', &
            'Dispersion correction for selected QM method is not supported.', &
            'Bye bye.')
    endif

   ! determine sp3 Carbons using distances
   ! Kyoyeon : we may want to change this to use bond orders instead of distances

   l_Csp3(:)=0

   if (qmtheory%PM6) then
      ! For PM6, the C6 value for sp3 carbon atoms has been reoptimized
      ! (Korth, Pitonak, Rezic, Hobza, JCTC 6, 344 (2010)
      do i=1,natom

         if (atomic_numbers(i) .eq. 6) then

            bond_count=0
            
            do j=1,natom
               if (j .ne. i) then
                  if (bo_matrix(i,j) .ge. parCutCsp3) then
                     bond_count = bond_count + 1
                  endif
               endif
            enddo
            
            if (bond_count .eq. 4) then
               l_Csp3(i)=1
            endif
            
         endif

      enddo

   end if
   
   ! calculate dispersion correction term

    corren=0.0d0

    do i=1,natom-1

       do j=i+1,natom

          vec(1:3) = xyz(1:3,i) - xyz(1:3,j)
          dist = vec(1)**2 + vec(2)**2 + vec(3)**2
          dist = dsqrt(dist)
 
          if (l_Csp3(i) .eq. 1) then
             iatom=108
          else
             iatom=atomic_numbers(i)
          endif
 
          if (l_Csp3(j) .eq. 1) then
             jatom=108
          else
             jatom=atomic_numbers(j)
          endif
 
          call get_c6_req(qmtheory,iatom,jatom,c6,req)
 
          req = req / 1000.d0 * 2.0d0
          dist = dist * 0.1d0 
 
          dum1 = -alpha * (dist / (sr * req) -1.d0)
          fdamp = 1.d0 / (1.d0 + dexp(dum1))
          dum2 = fdamp * c6 / dist**6
          corren = corren - dum2

       enddo

    enddo

    dCorrEner = corren * s6 * kjtokc / 1000.d0

  end subroutine calc_d_correction



! Calculate hydrogen bond correction
  subroutine calc_h_correction(natom,xyz,atomic_numbers,qmtheory, &
                               bo_matrix,hCorrEner, debug)

    use qmmm_qmtheorymodule, only : qmTheoryType
    
    implicit none
    
    integer, intent(in) :: natom
    _REAL_, intent(in) :: xyz(3,natom)
    integer, intent(in) :: atomic_numbers(natom)
    type(qmTheoryType), intent(in) :: qmtheory
    _REAL_, intent(in) :: bo_matrix(natom,natom)
    _REAL_, intent(out) :: hCorrEner
    logical, intent(in) :: debug

    _REAL_ :: parHCorr(natom)
    _REAL_ :: constN, constO
    _REAL_ :: const1, const2
    _REAL_ :: corren 
    _REAL_, parameter :: autokc = 627.509541d0
    _REAL_, parameter :: botoan = 0.52917726d0
    integer :: i, j, k

    if (debug) then
       write (6,'(a)') '>>>>> Entered calc_h_correction() (dh_correcton_module)'
       call flush(6)
    end if

    hCorrEner=0.0d0

    if (qmtheory%PM6) then
       constN=-0.16d0*autokc*botoan**2
       constO=-0.12d0*autokc*botoan**2
    else if (qmtheory%AM1) then
       constN=-0.29d0*autokc*botoan**2
       constO=-0.29d0*autokc*botoan**2
    else
       call sander_bomb('calc_d_correction (dh_correction_module)', &
            'Dispersion correction for selected QM method is not supported.', &
            'Bye bye.')
    endif

    parHCorr(:)=0.0d0

    do i=1,natom
       if (atomic_numbers(i) .eq. 7) then
          parHCorr(i)=constN
       else if (atomic_numbers(i) .eq. 8) then
          parHCorr(i)=constO
       endif
    enddo

    do i=1,natom-1
       if (atomic_numbers(i) .eq. 7 .or. atomic_numbers(i) .eq. 8) then
          do j=i+1,natom
             if (atomic_numbers(j) .eq. 7 .or. atomic_numbers(j) .eq. 8) then
                do k=1,natom
                   if (atomic_numbers(k) .eq. 1) then
                      if (bo_matrix(i,k) .ge. 0.5d0 .or. &
                          bo_matrix(j,k) .ge. 0.5d0) then
                         call calc_h_corr2(natom,xyz,atomic_numbers,bo_matrix, &
                                parHCorr(i), parHCorr(j), &
                                atomic_numbers(i), atomic_numbers(j), &
                                i,j,k,corren)
                         hCorrEner = hCorrEner + corren
                      endif        
                   endif
                enddo
             endif
          enddo
       endif
    enddo

    if (debug) then
       write (6,'(a)') '<<<<< Leaving calc_h_correction()'
       call flush(6)
    end if

  end subroutine calc_h_correction



  subroutine calc_h_corr2(natom,xyz,atomic_numbers,bo_matrix,const1,const2, &
                       itype,jtype,iatom,jatom,hatom,corren)

    implicit none

    integer, intent(in) :: natom
    integer, intent(in) :: iatom, jatom, hatom
    integer, intent(in) :: itype, jtype
    integer, intent(in) :: atomic_numbers(natom)
    _REAL_, intent(in) :: xyz(3,natom)
    _REAL_, intent(in) :: bo_matrix(natom,natom)
    _REAL_, intent(in) :: const1, const2

    _REAL_, intent(out) :: corren

    _REAL_ :: angAHD, ang1(2), ang2(2)
    _REAL_ :: distXH, distAD, dist
    _REAL_ :: fbond, fgeom, fdamp
    _REAL_ :: vec(3)
    _REAL_ :: shift, dih_check
    _REAL_ :: dum1, dum2, dum3
    integer :: adlist(2), ijtype(2)
    integer :: adbond_count(2), iadbond(2,natom-1)
    integer :: iadang1(2), iadang2(2), iadang3(2)
    integer :: i, j

    _REAL_, parameter :: pi = 3.14159265358979323846d0

    corren = 0.0d0

    ! adlist(*) - indice for donor or acceptor atoms
    ! hatom - index for hydrogen atom

    adlist(1) = iatom
    adlist(2) = jatom

    ijtype(1) = itype
    ijtype(2) = jtype

    adbond_count(:) = 0
    ang1(:) = 0.0d0
    ang2(:) = 0.0d0


    ! Calculate H---I distance 
    dum1 = Hdist(natom,xyz,adlist(1),hatom)

    ! Calculate H---J distance
    dum2 = Hdist(natom,xyz,adlist(2),hatom)

    ! distXH : distance between Hydrogen and donor atom
    distXH = min(dum1,dum2)

    ! Calculate distances between two electronegative atoms (acceptor & donor)
    distAD = Hdist(natom,xyz,adlist(1),adlist(2))

    ! Determine connectivity of donor and acceptor atoms
    do i=1,2
       do j=1,natom
          if (bo_matrix(j,adlist(i)) .ge. 0.5d0 .and. j .ne. adlist(i)) &
              then
             adbond_count(i) = adbond_count(i) + 1
             iadbond(i,adbond_count(i)) = j
          endif
       enddo
    enddo

    ! Too many bonds for O and N atoms - stop the simulation
    do i=1,2
       if (adbond_count(i) .gt. 4 .or. adbond_count(i) .eq. 0) then
          call sander_bomb('calc_h_corr2 (dh_correction_module)', &
               'Unusual bond definitions for H-bond correction.', &
               'Bye bye.')
       endif
    enddo

    ! iadang1, iadang2, iadang3 - indice for atoms connected to the dornor or
    ! acceptor atoms

    do i=1,2

    ! Assign the first connected atom

       dum1=0.0d0

       do j=1,adbond_count(i)
          if (iadbond(i,j) .ne. hatom) then
             dum2=Hdist(natom,xyz,hatom,iadbond(i,j))
             if (dum2 .ge. dum1) then
                iadang1(i)=iadbond(i,j)
                dum1=dum2
             endif
          endif
       enddo

       iadang2(i)=0
       iadang3(i)=0

    ! Assign remaining atoms

    ! XR3 case

       if (adbond_count(i) .ge. 3) then

          dum1=0.0d0

          do j=1,adbond_count(i)
             if (iadbond(i,j) .ne. hatom .and. &
                 iadbond(i,j) .ne. iadang1(i)) then
                dum2=Hdist(natom,xyz,hatom,iadbond(i,j))
                if (dum2 .ge. dum1) then
                   iadang2(i)=iadbond(i,j)
                   dum1=dum2
                endif
             endif
          enddo

          dum1=0.0d0

          do j=1,adbond_count(i)
             if (iadbond(i,j) .ne. hatom .and. &
                 iadbond(i,j) .ne. iadang1(i) .and. &
                 iadbond(i,j) .ne. iadang2(i)) then
                dum2=Hdist(natom,xyz,hatom,iadbond(i,j))
                if (dum2 .ge. dum1) then
                   iadang3(i)=iadbond(i,j)
                   dum1=dum2
                endif
             endif
          enddo

    ! XR2 case

       else if (adbond_count(i) .eq. 2) then

          dum1=0.0d0

          do j=1,adbond_count(i)
             if (iadbond(i,j) .ne. hatom .and. &
                 iadbond(i,j) .ne. iadang1(i)) then
                dum2=Hdist(natom,xyz,hatom,iadbond(i,j))
                if (dum2 .ge. dum1) then
                   iadang2(i)=iadbond(i,j)
                   dum1=dum2
                endif
             endif
          enddo

          if (iadang2(i) .ne. 0) then
             do j=1,natom
                if (bo_matrix(j,iadang2(i)) .ge. 0.5d0 .and. &
                    j .ne. iadang1(i) .and. j .ne. adlist(i)) then
                   dum1=0.0d0
                   dum2=Hdist(natom,xyz,hatom,j)
                   if (dum2 .ge. dum1) then
                      iadang3(i)=j
                      dum1=dum2
                   endif
                endif
             enddo
          endif

    ! XR case

       else if (adbond_count(i) .eq. 1) then

          do j=1,natom
             if (bo_matrix(j,iadang1(i)) .ge. 0.5d0 .and. &
                 j .ne. adlist(i)) then
                dum1=0.0d0
                dum2=Hdist(natom,xyz,hatom,j)
                if (dum2 .ge. dum1) then
                   iadang2(i)=j
                   dum1=dum2
                endif
             endif
          enddo

          do j=1,natom
             if (bo_matrix(j,iadang1(i)) .ge. 0.5d0 .and. &
                 j .ne. adlist(i) .and. j .ne. iadang2(i)) then
                dum1=0.0d0
                dum2=Hdist(natom,xyz,hatom,j)
                if (dum2 .ge. dum1) then
                   iadang3(i)=j
                   dum1=dum2
                endif
             endif
          enddo

          if (iadang3(i) .eq. 0) then
             do j=1,natom
                if (bo_matrix(j,iadang2(i)) .ge. 0.5d0 .and. &
                    j .ne. iadang1(i)) then
                   dum1=0.0d0
                   dum2=Hdist(natom,xyz,hatom,j)
                   if (dum2 .ge. dum1) then
                      iadang3(i)=j
                      dum1=dum2
                   endif
                endif
             enddo
          endif

       endif

    enddo 

    ! End of defining connectivity of atoms


    ! Angle for Donnor --- H --- Acceptor

    angAHD=Hangle(natom,xyz,adlist(1),hatom,adlist(2))

    ! If Donnor-Hydrogen-Acceptor angle is too small (distorted), 
    ! do not calculate H-Bond contribution.
    if (-dcos(angAHD) .le. 0.0d0) then
       return
    endif


    ! Angles for R2 - X - H

    do i=1,2

    ! Set the ideal angles
    ! Oxygen case
       if (atomic_numbers(adlist(i)) .eq. 8) then
          if (adbond_count(i) .eq. 1) then
             shift=pi
          else
             shift=pi*109.48d0/180.d0
          endif
    ! Nitrogen case
       else if (atomic_numbers(adlist(i)) .eq. 7) then
          if (adbond_count(i) .eq. 2) then
             shift=pi*120.d0/180.d0
          else
             shift=pi*109.48d0/180.d0
          endif
       endif

       ang1(i)=shift-Hangle(natom,xyz,hatom,adlist(i),iadang1(i))

    ! Correction for -C=O---H case
       if (atomic_numbers(adlist(i)) .eq. 8 .and. adbond_count(i) .eq. 1) then
          dum3=ang1(i)-shift+pi*120.d0/180.d0
          if (dcos(dum3) .gt. dcos(ang1(i))) then
             ang1(i)=dum3
          endif
       endif

    ! If the difference of the ideal angle and the actual R2-X-H angle is too
    ! big, do not calculate H-Bond contribution.
       if (dcos(ang1(i)) .lt. 0.0d0) then
          return
       endif

    enddo


    ! Dihedral angles for R1 - R2 - X - H 

    do i=1,2

       dum1=Hdist(natom,xyz,hatom,adlist(i))
       dum2=Hdist(natom,xyz,hatom,iadang1(i))

    ! Distorted -C=O--H case : H-Bond contribution is zero
       if ((atomic_numbers(adlist(i)) .eq. 8 .and. adbond_count(i) .eq. 1) &
           .and. (dum1 .gt. dum2)) then

          return

    ! General cases
       else

    ! Set the ideal angles
    ! O case
          if (atomic_numbers(adlist(i)) .eq. 8) then
             if (adbond_count(i) .eq. 1) then
                shift=0.0d0
             else
                shift=pi*54.74d0/180.d0
             endif
    ! N case
          else if (atomic_numbers(adlist(i)) .eq. 7) then
             if (adbond_count(i) .eq. 2) then
                shift=0.0d0
             else
                shift=pi*54.74d0/180.d0
             endif
          endif


          if (iadang2(i) .ne. 0 .and. iadang3(i) .ne. 0) then
    
             ang2(i)=Hdihedral(natom,xyz,hatom,adlist(i),iadang1(i),iadang2(i))
           
             if (ang2(i) .le. -pi) then
                ang2(i)=ang2(i)+2.0d0*pi
             else if (ang2(i) .gt. pi) then
                ang2(i)=ang2(i)-2.0d0*pi
             endif
           
             if (.not.(atomic_numbers(adlist(i)) .eq. 8 .and. adbond_count(i) .eq. 1) &
                 .or. (abs(ang2(i)*180.d0/pi) .gt. 90.d0)) then
    
                if (ang2(i) .lt. 0.0d0) then
                   ang2(i)=-pi-ang2(i)
                else
                   ang2(i)=pi-ang2(i)
                endif
    
             endif
    
             dih_check=0.0d0
    
    ! Set parameters for planner NR3 group correction
             if ((atomic_numbers(adlist(i)) .eq. 7) .and.  &
                      (adbond_count(i) .ge. 3)) then
    
                dih_check=Hdihedral(natom,xyz,iadang2(i),iadang1(i),adlist(i),iadang3(i))
  
                if (dih_check .le. -pi) then
                   dih_check=dih_check+2.0d0*pi
                else if (dih_check .gt. pi) then
                   dih_check=dih_check-2.0d0*pi
                endif
  
                if (dih_check .lt. 0.0d0) then
                   dih_check=-pi-dih_check
                else
                   dih_check=pi-dih_check
                endif
  
                dum2=abs(dih_check)
                dum2=dum2*180.d0/pi
                shift= shift + pi/(180.d0/((54.74d0-dum2)/54.74d0*35.26d0))
                ang1(i)=ang1(i)-pi/(180.d0/((54.74d0-dum2)/54.74d0*19.48d0))
     
             endif
    
    ! End of setting parameters for NR3 correction

             if (dih_check .lt. 0.0d0) then
                ang2(i)=shift-ang2(i)
             else if (dum1 .gt. 0.0d0) then
                ang2(i)=-shift-ang2(i)
             else

                dum2=shift-ang2(i)
                dum3=-shift-ang2(i)

                if (dum2 .le. -pi) then
                   dum2=dum2+2.0d0*pi
                else if (dum2 .gt. pi) then
                   dum2=dum2-2.0d0*pi
                endif

                if (dum3 .le. -pi) then
                   dum3=dum3+2.0d0*pi
                else if (dum3 .gt. pi) then
                   dum3=dum3-2.0d0*pi
                endif

                if (dcos(dum2) .gt. dcos(dum3)) then
                   ang2(i)=dum2
                else
                   ang2(i)=dum3
                endif

             endif

             if (ang2(i) .le. -pi) then
                ang2(i)=ang2(i)+2.0d0*pi
             else if (ang2(i) .ge. pi) then
                ang2(i)=ang2(i)-2.0d0*pi
             endif
    
          else
    
             ang2(i)=0.0d0
    
          endif

       endif

    ! Too much distorted structure, no H-Bond contribution

       if (dcos(ang2(i)) .lt. 0.0d0) then
          return
       endif

    enddo


    ! Calculate F_geom term
    dum1 = -60.0d0 * ((distXH/1.2d0) - 1.0d0)
    dum1 = 1.0d0 + dexp(dum1)
    fbond = 1.0d0 - (1.0d0/dum1)
    fgeom = dcos(angAHD)**2 * dcos(ang1(1))**2 * dcos(ang1(2))**2 &
            * dcos(ang2(1))**2 * dcos(ang2(2))**2 * fbond

    ! Calculate damping function
    dum1 = 1.0d0 + dexp(-100.0d0*((distAD/2.4d0)-1.0d0))
    dum2 = 1.0d0 + dexp(-10.0d0*((distAD/7.0d0)-1.0d0))
    fdamp = (1.0d0/dum1) * (1.0d0 - (1.0d0/dum2))

    ! Calculate energy correction for hydrogen bond
    corren = ((const1 + const2) / 2.0d0) * fgeom * fdamp / distAD**2


  end subroutine calc_h_corr2



! Calculate bond order matrix
! Copied from "qm2_print_bondorders" subroutine
  subroutine calc_bo_matrix(qm2_params,qm2_struct,natom,bo_matrix)

  ! Requires a converged density matrix stored in qm2_struct%den_matrix
  use qm2_params_module,  only : qm2_params_type
  use qmmm_module, only : qm2_structure

  implicit none

  type(qm2_params_type),intent(inout) :: qm2_params
  type(qm2_structure),target :: qm2_struct
  integer, intent(in) :: natom
  _REAL_, intent(out) :: bo_matrix(natom,natom)

  integer :: orb_beg_i, orb_end_i, tri_i
  integer :: orb_beg_j, orb_end_j, tri_j, tri
  integer :: i,j,k, tri_k1, tri_k2, iqm, jqm
  _REAL_, dimension(:), pointer :: den_matrix2
  _REAL_ :: BO


  bo_matrix(:,:)=0.0d0

  ! CALCULATE THE BOND ORDERS
  do iqm = 1,natom

     orb_beg_i=qm2_params%orb_loc(1,iqm)
     orb_end_i=qm2_params%orb_loc(2,iqm)

     do jqm = 1,iqm-1

        orb_beg_j=qm2_params%orb_loc(1,jqm)
        orb_end_j=qm2_params%orb_loc(2,jqm)

        BO = 0

        do i=orb_beg_i,orb_end_i
           do j=orb_beg_j,orb_end_j
              tri = qm2_params%pascal_tri1(i)+j
              BO = BO + qm2_struct%den_matrix(tri)*qm2_struct%den_matrix(tri)
           end do
        end do

        bo_matrix(iqm,jqm)=BO
        bo_matrix(jqm,iqm)=BO

     end do

  end do

  end subroutine calc_bo_matrix



! Mix atomic coefficients to obtain C6ij and R0ij
  subroutine get_c6_req(qmtheory,iatom,jatom,c6,req)

    use qmmm_qmtheorymodule, only : qmTheoryType
    implicit none

    type(qmTheoryType), intent(in) :: qmtheory
    integer, intent(in) :: iatom, jatom

    _REAL_, intent(out) :: c6, req

    ! C6ii constants (J * nm^6 / mol)

    _REAL_ :: c6const(108)

    data c6const / &
    !      H       He
         & 0.16d0, 0.08d0, &
    !      Li      Be      B       C       N       O       F       Ne
         & 999.d0, 999.d0, 5.79d0, 1.65d0, 1.11d0, 0.70d0, 0.36d0, 0.45d0, &
    !      Na      Mg      Al      Si      P       S       Cl      Ar
         & 999.d0, 999.d0, 999.d0, 14.8d0, 3.25d0, 5.79d0, 5.97d0, 3.71d0, &
    !      K       Ca      Sc      Ti      V       Cr      Mn      Fe
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Co      Ni      Cu      Zn      Ga      Ge      As      Se
         & 0.04d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Br      Kr
         & 11.6d0, 4.47d0, &
    !      Rb      Sr      Y       Zr      Nb      Mo      Tc      Ru
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Rh      Pd      Ag      Cd      In      Sn      Sb      Te
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      I       Xe
         & 25.8d0, 16.5d0, &
    !      Cs      Ba      La      Ce      Pr      Nd      Pm      Sm
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Eu      Gd      Tb      Dy      Ho      Er      Tm      Yb
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Lu      Hf      Ta      W       Re      Os      Ir      Pt
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Au      Hg      Tl      Pb      Bi      Po      At      Rn
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Fr      Ra      Ac      Th      Pa      U       Np      Pu
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Am      Cm      Bk      Cf      Es      Fm      Md      No
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Lr      Rf      Db      Sg       Tv
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Csp3 (sp3 carbon)
         & 0.95d0 /


    ! Slater-Kirkwood effective number of electrons

    _REAL_ :: neffelec(108)

    data neffelec / &
    !      H       He
         & 0.80d0, 1.42d0, &
    !      Li      Be      B       C       N       O       F       Ne
         & 999.d0, 999.d0, 2.16d0, 2.50d0, 2.82d0, 3.15d0, 3.48d0, 3.81d0, &
    !      Na      Mg      Al      Si      P       S       Cl      Ar
         & 999.d0, 999.d0, 999.d0, 4.20d0, 4.50d0, 4.80d0, 5.10d0, 5.40d0, &
    !      K       Ca      Sc      Ti      V       Cr      Mn      Fe
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Co      Ni      Cu      Zn      Ga      Ge      As      Se
         & 2.90d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Br      Kr
         & 6.00d0, 6.30d0, &
    !      Rb      Sr      Y       Zr      Nb      Mo      Tc      Ru
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Rh      Pd      Ag      Cd      In      Sn      Sb      Te
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      I       Xe
         & 6.95d0, 7.25d0, & 
    !      Cs      Ba      La      Ce      Pr      Nd      Pm      Sm
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Eu      Gd      Tb      Dy      Ho      Er      Tm      Yb
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Lu      Hf      Ta      W       Re      Os      Ir      Pt
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Au      Hg      Tl      Pb      Bi      Po      At      Rn
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Fr      Ra      Ac      Th      Pa      U       Np      Pu
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Am      Cm      Bk      Cf      Es      Fm      Md      No
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Lr      Rf      Db      Sg       Tv
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Csp3 (sp3 carbon)
         & 2.50d0 /


    ! Bondii vdW radii (pm)
    ! from A. Bondii, J. Phys. Chem. 68, 441 (1964).

    _REAL_ :: vdwr(108)

    data vdwr / &
    !      H       He
         & 120.d0, 140.d0, &
    !      Li      Be      B       C       N       O       F       Ne
         & 999.d0, 999.d0, 180.d0, 170.d0, 155.d0, 152.d0, 147.d0, 154.d0, &
    !      Na      Mg      Al      Si      P       S       Cl      Ar
         & 999.d0, 999.d0, 999.d0, 210.d0, 180.d0, 180.d0, 175.d0, 188.d0, &
    !      K       Ca      Sc      Ti      V       Cr      Mn      Fe
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Co      Ni      Cu      Zn      Ga      Ge      As      Se
         & 140.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 185.d0, 190.d0, &
    !      Br      Kr
         & 185.d0, 202.d0, &
    !      Rb      Sr      Y       Zr      Nb      Mo      Tc      Ru
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Rh      Pd      Ag      Cd      In      Sn      Sb      Te
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 206.d0, &
    !      I       Xe
         & 198.d0, 216.d0, &
    !      Cs      Ba      La      Ce      Pr      Nd      Pm      Sm
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Eu      Gd      Tb      Dy      Ho      Er      Tm      Yb
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Lu      Hf      Ta      W       Re      Os      Ir      Pt
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Au      Hg      Tl      Pb      Bi      Po      At      Rn
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Fr      Ra      Ac      Th      Pa      U       Np      Pu
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Am      Cm      Bk      Cf      Es      Fm      Md      No
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Lr      Rf      Db      Sg       Tv
         & 999.d0, 999.d0, 999.d0, 999.d0, 999.d0, &
    !      Csp3 (sp3 carbon)
         & 170.d0 /


    _REAL_ :: dum1, dum2, dum3
    _REAL_ :: c6ii, c6jj
    _REAL_ :: neffii, neffjj
    _REAL_ :: rii, rjj


    ! For PM6, the vdW radius of hydrogen has been reoptimized 
    ! (Korth, Pitonak, Rezic, Hobza, JCTC 6, 344 (2010)
    if (qmtheory%PM6) then
       vdwr(1) = 156.0d0
    end if

    ! Check whether parameters are available for elements

    if (c6const(iatom) .ge. 999.d0 &
        .or. c6const(jatom) .ge. 999.d0 &
        .or. neffelec(iatom) .ge. 999.d0 &
        .or. neffelec(jatom) .ge. 999.d0 &
        .or. vdwr(iatom) .ge. 999.d0 &
        .or. vdwr(jatom) .ge. 999.d0 ) then

       call sander_bomb('get_c6_req (dh_correction_module)', &
            'Parameters for dispersion correction are not available for this atom.', &
            'Bye bye.')
    endif



    c6ii=c6const(iatom)
    c6jj=c6const(jatom)
    neffii=neffelec(iatom)
    neffjj=neffelec(jatom)
    rii=vdwr(iatom)
    rjj=vdwr(jatom)


    ! Mix C6ij

    dum1 = c6ii**2 * c6jj**2 * neffii * neffjj
    dum1 = dum1**(1.d0/3.d0)
    dum2 = c6ii * neffjj**2
    dum2 = dum2**(1.d0/3.d0)
    dum3 = c6jj * neffii**2
    dum3 = dum3**(1.d0/3.d0)

    c6 = 2.d0 * ( dum1 / (dum2 + dum3) )

    ! Mix R0ij

    req = (rii**3 + rjj**3) / (rii**2 + rjj**2)

  end subroutine get_c6_req


  ! -------------------------------------
  ! Print information about theory in use
  ! -------------------------------------
  subroutine dh_correction_info(qmtheory)

    use qmmm_qmtheorymodule, only : qmTheoryType

    implicit none

    type(qmTheoryType), intent(in) :: qmtheory
    
    if (qmtheory%DISPERSION .or. qmtheory%DISPERSION_HYDROGENPLUS) then
       write(6,'(/a)') '| QMMM: *** Dispersion correction in use ***'
       write(6,'(a)')  '| QMMM: P. Jurecka et al, J. Comput. Chem., 28, 555 (2007)'
       write(6,'(a)')  '| QMMM: with parameters from'
       write(6,'(a)')  '| QMMM: M. Kort et al, J. Chem. Theory Comput., 6, 344 (2010)'
    endif

    ! print also parameters (maybe)

    if (qmtheory%DISPERSION_HYDROGENPLUS) then
       write(6,'(/a)') '| QMMM: *** Hydrogen bond correction in use ***'
       write(6,'(a)')  '| QMMM: Kort, J. Chem. Theory Comput., 6, 3808 (2010)'
    end if

  end subroutine dh_correction_info


  _REAL_ function Hdist(natom,xyz,iatom,jatom)

    implicit none

    _REAL_ :: xyz(3,natom)
    _REAL_ :: vec(3), dum
    integer :: natom
    integer :: iatom, jatom

    vec(1:3) = xyz(1:3,iatom) - xyz(1:3,jatom)
    dum = vec(1)**2 + vec(2)**2 + vec(3)**2
    Hdist = dsqrt(dum)

  end function Hdist


  _REAL_ function Hangle(natom,xyz,iatom,jatom,katom)

    implicit none

    _REAL_ :: xyz(3,natom)
    _REAL_ :: vec1(3), vec2(3)
    _REAL_ :: ra, rb, dum
    integer :: natom
    integer :: iatom, jatom, katom

    vec1(1:3) = xyz(1:3,iatom) - xyz(1:3,jatom)
    vec2(1:3) = xyz(1:3,katom) - xyz(1:3,jatom)

    ra = vec1(1)**2 + vec1(2)**2 + vec1(3)**2
    ra = dsqrt(ra)

    rb = vec2(1)**2 + vec2(2)**2 + vec2(3)**2
    rb = dsqrt(rb)

    dum = (vec1(1)*vec2(1) + vec1(2)*vec2(2) + vec1(3)*vec2(3)) &
            / (ra * rb)

    if (dum .gt. 1.0d0) dum=1.0d0
    if (dum .lt. -1.0d0) dum=-1.0d0

    Hangle=dacos(dum)


  end function Hangle


  _REAL_ function Hdihedral(natom,xyz,iatom,jatom,katom,latom)

    implicit none

    _REAL_ :: xyz(3,natom)
    _REAL_ :: vec1(3), vec2(3), vec3(3)
    _REAL_ :: ax, ay, az, bx, by, bz, ra, rb
    _REAL_ :: dum, dum1, dum2, dum3, dum4
    integer :: natom
    integer :: iatom, jatom, katom, latom

    vec1(1:3) = xyz(1:3,jatom) - xyz(1:3,iatom)
    vec2(1:3) = xyz(1:3,katom) - xyz(1:3,jatom)
    vec3(1:3) = xyz(1:3,latom) - xyz(1:3,katom)

    ax = vec1(2)*vec2(3) - vec1(3)*vec2(2)
    ay = vec1(3)*vec2(1) - vec1(1)*vec2(3)
    az = vec1(1)*vec2(2) - vec1(2)*vec2(1)
    bx = vec2(2)*vec3(3) - vec2(3)*vec3(2)
    by = vec2(3)*vec3(1) - vec2(1)*vec3(3)
    bz = vec2(1)*vec3(2) - vec2(2)*vec3(1)

    ra = dsqrt(ax**2 + ay**2 + az**2)
    rb = dsqrt(bx**2 + by**2 + bz**2)

    dum = (ax*bx + ay*by + az*bz) / (ra*rb)

    if (dum .gt. 1.0d0) dum=1.0d0
    if (dum .lt. -1.0d0) dum=-1.0d0

    dum1 = ay*bz - az-by
    dum2 = az*bx - ax*bz
    dum3 = ax*by - ay*bx
    dum4 = dum1*vec2(1) + dum2*vec2(2) + dum3*vec2(3)

    if (dum4 .ge. 0.0d0) then
       Hdihedral=dacos(dum)
    else
       Hdihedral=-dacos(dum)
    endif

    

  end function Hdihedral


end module dh_correction_module
