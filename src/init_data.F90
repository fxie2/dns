!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!Copyright 2007.  Los Alamos National Security, LLC. This material was
!produced under U.S. Government contract DE-AC52-06NA25396 for Los
!Alamos National Laboratory (LANL), which is operated by Los Alamos
!National Security, LLC for the U.S. Department of Energy. The
!U.S. Government has rights to use, reproduce, and distribute this
!software.  NEITHER THE GOVERNMENT NOR LOS ALAMOS NATIONAL SECURITY,
!LLC MAKES ANY WARRANTY, EXPRESS OR IMPLIED, OR ASSUMES ANY LIABILITY
!FOR THE USE OF THIS SOFTWARE.  If software is modified to produce
!derivative works, such modified software should be clearly marked, so
!as not to confuse it with the version available from LANL.
!
!Additionally, this program is free software; you can redistribute it
!and/or modify it under the terms of the GNU General Public License as
!published by the Free Software Foundation; either version 2 of the
!License, or (at your option) any later version. Accordingly, this
!program is distributed in the hope that it will be useful, but WITHOUT
!ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
!FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
!for more details.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#include "macros.h"
subroutine init_data(Q,Qhat,q1,work1,work2)
use params
use mpi
implicit none
real*8 :: Q(nx,ny,nz,n_var)
real*8 :: Qhat(nx,ny,nz,n_var)
real*8 :: q1(nx,ny,nz,n_var)
real*8 :: work1(nx,ny,nz)
real*8 :: work2(nx,ny,nz)
real*8 :: divx,divi
character(len=280) :: fname
character(len=80) message

if (restart==1) then

   ! initialize some constants, if needed on restart runs:

   ! set grav, fcor
   if (init_cond==3) call init_data_sht(Q,Qhat,work1,work2,0)   
   if (init_cond==10) call init_3d_rot(Q,Qhat,work1,work2,0)   

   ! set xscale, yscale, offset grid 
   if (init_cond==4) call init_data_vxpair(Q,Qhat,work1,work2,0)   

   !
   ! read input uvw data from restart files.  sets 'time_initial'
   ! from restart data
   !
   call init_data_restart(Q,Qhat,work1,work2)

   ! set boundary data using input data.
   if (init_cond==4) call init_data_vxpair(Q,Qhat,work1,work2,2)  

   ! rescale Energy spectrum
   if (init_cond==9) then
      call init_data_decay(Q,Qhat,work1,work2,2,0,0)
      ! output rescaled data, but with different name:
      fname=runname(1:len_trim(runname)) // '-rescale'
      call output_uvw(fname,time_initial,Q,Qhat,work1,work2,header_user)
   endif

   if (npassive>0) then
   if (compute_passive_on_restart) then
      call init_passive_scalars(1,Q,Qhat,work1,work2)
      ! restart runs wont output data at t=0, for scalar output:
      call output_passive(runname,time_initial,Q,q1,work1,work2)	
   else
      call init_passive_scalars(0,Q,Qhat,work1,work2)
      call input_passive(runname,time_initial,Q,work1,work2,header_user)
   endif
   endif

else
   if (init_cond==0) call init_data_khblob(Q,Qhat,work1,work2)  ! KH-blob
   if (init_cond==1) call init_data_kh(Q,Qhat,work1,work2)      ! KH-anal
   if (init_cond==2) call init_data_lwisotropic(Q,Qhat,work1,work2,1,0) ! iso12
   if (init_cond==3) call init_data_sht(Q,Qhat,work1,work2,1)          ! sht
   if (init_cond==4) call init_data_vxpair(Q,Qhat,work1,work2,1)       ! vxpair  
   if (init_cond==5) call init_data_lwisotropic(Q,Qhat,work1,work2,1,1) ! iso12e
   if (init_cond==6) call init_data_zero(Q,Qhat,work1,work2)            ! zero
   if (init_cond==7) call init_data_decay(Q,Qhat,work1,work2,1,0,0)     ! decay2048
   if (init_cond==8) call init_data_decay(Q,Qhat,work1,work2,1,1,0)     ! decay2048_e
   if (init_cond==10) call init_3d_rot(Q,Qhat,work1,work2,1)            ! 3d_rot 
   if (init_cond==11) call init_TG(Q,Qhat,work1,work2)                  ! Taylor Green
   if (init_cond==12) call init_EDQMN(Q,Qhat,work1,work2)                  !

   if (npassive>0) then
      call init_passive_scalars(1,Q,Qhat,work1,work2)
   endif

   !balu: because first passive scalar gets set to 0 by init_passive_scalars
   if (init_cond==13) call init_thrmlwnd(Q,Qhat,work1,work2)                  !

   if (equations==NS_UVW) then
      call print_message('Projecting and dealiasing initial data...')
      call divfree_gridspace(Q,work1,work2,q1) 
   else if (dealias>0)  then
      call print_message('Dealiasing initial data...')
   endif
endif

call compute_div(Q,q1,work1,work2,divx,divi)
write(message,'(3(a,e12.5))') 'inputdata:  max(div)=',divx
call print_message(message)	



end subroutine









subroutine init_data_restart(Q,Qhat,work1,work2)
!
!
!
use params
use pdf
use mpi
implicit none
real*8 :: Q(nx,ny,nz,n_var)
real*8 :: Qhat(nx,ny,nz,n_var)
real*8 :: work1(nx,ny,nz)
real*8 :: work2(nx,ny,nz)

!local
character(len=80) message
character(len=80) fname
integer :: n,ierr
CPOINTER :: fid

Q=0
time_initial=-1
call input_uvw(time_initial,Q,Qhat,work1,work2,header_user)

if (diag_pdfs /= 0) then
   if (my_pe==io_pe) then
      ! see if there is a restart.cpdf file:
      call copen(rundir(1:len_trim(rundir)) // "restart.cpdf","r",fid,ierr)
      if (ierr/=0) then
         print *,"Could not open restart.cpdf file. code will recompute PDF binsizes"
      else
         call read_cpdf_binsize(fid)
         call cclose(fid,ierr)
         print *,"PDF binsizes succesfully read from restart.cpdf file"
      endif
#ifdef USE_MPI
      call mpi_bcast(number_of_cpdf_restart,1,MPI_INTEGER,io_pe,comm_3d ,ierr)
      if (number_of_cpdf_restart>0) &
           call mpi_bcast(cpdf_restart_binsize,number_of_cpdf_restart,MPI_REAL8,io_pe,comm_3d ,ierr)
#endif
   else
#ifdef USE_MPI
      call mpi_bcast(number_of_cpdf_restart,1,MPI_INTEGER,io_pe,comm_3d ,ierr)
      if (number_of_cpdf_restart>0) then
         allocate(cpdf_restart_binsize(number_of_cpdf_restart))
         call mpi_bcast(cpdf_restart_binsize,number_of_cpdf_restart,MPI_REAL8,io_pe,comm_3d ,ierr)
      endif
#endif
   endif
endif




write(message,'(a,f10.4)') "restart time=",time_initial
call print_message(message)

end subroutine










subroutine init_passive_scalars(init,Q,Qhat,work1,work2)
!
! low wave number, quasi isotropic initial condition
!
! init=0    initialize schmidt number only
! init=1    initialize schmidt number and passive scalar data
!
!
use params
implicit none
real*8 :: Q(nx,ny,nz,n_var)
real*8 :: Qhat(nx,ny,nz,n_var)
real*8 :: work1(nx,ny,nz)
real*8 :: work2(nx,ny,nz)
real*8 :: xfac,mn,mx,ke_percent
integer :: n,k,i,j,im,jm,km,init,count,iter,n1
character(len=80) :: message


if (my_pe==io_pe) then
   print *,"passive scalars:"
   print *,"    n   Schmidt   Type (0=Gaussian, 1=KE based)"
   do n=np1,np2
      write(*,'(i4,f11.3,i7)') n-np1+1,schmidt(n),passive_type(n)
   enddo
endif


if (init==0) return

count=0
do n=np1,np2

   count=count+1
   if (mod(count,2)==1) then
      n1=np1
   else
      n1=np1+1
   endif

   if (count>2 .and. passive_type(n)==passive_type(n1)) then
      write(message,'(a,i3)') 'Re-using i.c. from passive scalar ',n1
      call print_message(message)
      Q(:,:,:,n)=Q(:,:,:,n1) 
   else
      if (passive_type(n)==0) call passive_gaussian_init(Q,work1,work2,n)
      if (passive_type(n)==1) then
         ke_percent=.77
         call passive_KE_init(Q,work1,work2,n,ke_percent)
      endif
      if (passive_type(n)==2) Q(:,:,:,n)=0
      if (passive_type(n)==3) then
         ke_percent=.5
         call passive_KE_init(Q,work1,work2,n,ke_percent)
      endif
      if (passive_type(n)==4) then
!sk test passive_bous_init         
	Q(:,:,:,n)=0
!	call passive_bous_init(Q,work1,work2,n)
      endif


      call global_min(Q(1,1,1,n),mn)
      call global_max(Q(1,1,1,n),mx)
      
      write(message,'(a,2f17.5)') 'initial passive scalar min/max: ',mn,mx
      call print_message(message)	

      ! skip smoothing step ?
      if (passive_type(n)==2 .or. passive_type(n)==4) exit  


      call print_message("smothing passive scalar...")
      ! filter
      call fft3d(Q(1,1,1,n),work1)
      call fft_filter_dealias(Q(1,1,1,n))

      work2=Q(:,:,:,n)
      call ifft3d(work2,work1)
      call global_min(work2,mn)
      call global_max(work2,mx)
      
      ! laplacian smoothing:
      ! du/dt  =  laplacian(u)
      !  u_k = ((1 - k**2))**p  u_k    p = number of timesteps
      ! iterate until max and mn are within 5% of 0 and 1.  max iter=40
      iter=0
      do while ((mx>1.05 .or. mn<-.05) .and. (count<40) )
         iter=iter+1
         do k=nz1,nz2
            km=abs(kmcord(k))
            do j=ny1,ny2
               jm=abs(jmcord(j))
               do i=nx1,nx2
                  im=abs(imcord(i))
                  
                  xfac=(im*im+jm*jm+km*km)
                  xfac=xfac/(.25*g_nx*g_nx + .25*g_ny*g_ny + .25*g_nz*g_nz)
                  xfac=(1-.40*xfac)
                  
                  Q(i,j,k,n)=Q(i,j,k,n)*xfac
               enddo
            enddo
         enddo
         if (iter>=10) then  ! start checking 'mx'
            work2=Q(:,:,:,n)
            call ifft3d(work2,work1)
            call global_min(work2,mn)
            call global_max(work2,mx)
         endif
      enddo
      call ifft3d(Q(1,1,1,n),work1)
      write(message,'(a,2f17.5,a,i3)') 'after smoothing: min/max: ',mn,mx,'  iter=',iter
      call print_message(message)	
   endif
enddo


end subroutine








subroutine passive_KE_init(Q,work1,work2,np,ke_percent)
!
! low wave number, quasi isotropic initial condition
!
use params
use mpi
implicit none
integer :: np
real*8 :: Q(nx,ny,nz,n_var)
real*8 :: work1(nx,ny,nz)
real*8 :: work2(nx,ny,nz)

real*8 :: ke2,ke,ke_thresh,check,ke_percent
integer :: i,j,k,n,ierr

character(len=80) ::  message

write(message,'(a,i3,a)') "Initializing KE correlated double delta passive scalar n=",np
call print_message(message)

ke=0
do n=1,ndim
   do k=nz1,nz2
   do j=ny1,ny2
   do i=nx1,nx2
      ke = ke + .5*Q(i,j,k,n)**2
   enddo
   enddo
   enddo
enddo
ke=ke/g_nx/g_ny/g_nz

#ifdef USE_MPI
   ke2=ke
   call mpi_allreduce(ke2,ke,1,MPI_REAL8,MPI_SUM,comm_3d,ierr)
#endif


 
ke_thresh=ke_percent*ke  ! .82 has too much 0, not enough 1 at 256^3
! .77 has a touch too much at 1, not enought at 0

Q(:,:,:,np)=0
check=0
do k=nz1,nz2
   do j=ny1,ny2
      do i=nx1,nx2

         ke = .5*Q(i,j,k,1)**2
         do n=2,ndim
            ke = ke + .5*Q(i,j,k,n)**2
         enddo

         if (ke>ke_thresh) then
            Q(i,j,k,np)=1
            check=check+1
         endif
      enddo
   enddo
enddo

check=check/g_nx/g_ny/g_nz
#ifdef USE_MPI
   ke2=check
   call mpi_allreduce(ke2,check,1,MPI_REAL8,MPI_SUM,comm_3d,ierr)
#endif


write(message,'(a,f7.3)') "Mean density: ",check
call print_message(message)


end subroutine













subroutine passive_gaussian_init(Q,work1,work2,np)
!
! low wave number, quasi isotropic initial condition
!
use params
use transpose
implicit none
integer :: np
real*8 :: Q(nx,ny,nz,n_var)
real*8 :: work1(nx,ny,nz)
real*8 :: work2(nx,ny,nz)

real*8 :: ke2,ke,ke_thresh,check
integer :: i,j,k,n,ierr,NUMBANDS
real*8,allocatable :: enerb_target(:)
real*8,allocatable :: enerb(:)
real*8 :: ener
CPOINTER :: null
character(len=80) ::  message

write(message,'(a,i3,a)') "Initializing double delta passive scalars n=",np," ..."
call print_message(message)


NUMBANDS=.5 + sqrt(2.0)*g_nmin/3  ! round up
allocate(enerb_target(NUMBANDS))
allocate(enerb(NUMBANDS))

call livescu_spectrum(enerb_target,NUMBANDS,1,init_cond_subtype)

call input1(Q(1,1,1,np),work1,work2,null,io_pe,.true.,-1)  
call rescale_e(Q(1,1,1,np),work1,ener,enerb,enerb_target,NUMBANDS,1,1)
! convert to 0,1:
do k=nz1,nz2
do j=ny1,ny2
do i=nx1,nx2
   if (Q(i,j,k,np)<0) then
      Q(i,j,k,np)=0
   else
      Q(i,j,k,np)=1
   endif
enddo
enddo
enddo

deallocate(enerb_target)
deallocate(enerb)
end subroutine


subroutine passive_bous_init(Q,work1,work2,np)
!
! low wave number, quasi isotropic initial condition
!
use params
use transpose
implicit none
integer :: np
real*8 :: Q(nx,ny,nz,n_var)
real*8 :: work1(nx,ny,nz)
real*8 :: work2(nx,ny,nz)

real*8 :: ke2,ke,ke_thresh,check
integer :: i,j,k,n,ierr,NUMBANDS
real*8,allocatable :: enerb_target(:)
real*8,allocatable :: enerb(:)
real*8 :: ener
CPOINTER :: null
character(len=80) ::  message

write(message,'(a,i3,a)') "Initializing boussinesq passive scalars n=",np," ..."
call print_message(message)


NUMBANDS=5
allocate(enerb_target(NUMBANDS))
allocate(enerb(NUMBANDS))
enerb_target(1:NUMBANDS)=1.0


call input1(Q(1,1,1,np),work1,work2,null,io_pe,.true.,-1)  
call rescale_e(Q(1,1,1,np),work1,ener,enerb,enerb_target,NUMBANDS,1,1)

deallocate(enerb_target)
deallocate(enerb)
end subroutine










subroutine ranvor(Q,PSI,work,work2,rantype)
!
!  rantype==0    reproducable with different parallel decompositions, slow
!  rantype==1    fast, not reproducable
!
!
use params
use transpose
implicit none
real*8 :: Q(nx,ny,nz,3)
real*8 :: PSI(nx,ny,nz,3)
real*8 :: work(nx,ny,nz)
real*8 :: work2(nx,ny,nz)
integer :: rantype,n,im,jm,km,i,j,k
real*8 :: xfac,alpha,beta
character(len=80) :: message
CPOINTER :: null


call print_message("computing random initial vorticity")
!random vorticity
if (rantype==0) then
do n=1,3
   ! input from random number generator
   ! this gives same I.C independent of cpus
   call input1(PSI(1,1,1,n),work2,work,null,io_pe,.true.,-1)  
enddo
else if (rantype==1) then
   do n=1,3
   write(message,*) 'random initial vorticity n=',n   
   call print_message(message)
   do k=nz1,nz2
      km=kmcord(k)
      do j=ny1,ny2
         jm=jmcord(j)
         call gaussian( PSI(nx1,j,k,n), nslabx  )
         do i=nx1,nx2
            im=imcord(i)
            xfac = (2*2*2)
            if (km==0) xfac=xfac/2
            if (jm==0) xfac=xfac/2
            if (im==0) xfac=xfac/2
            PSI(i,j,k,n)=PSI(i,j,k,n)/xfac
         enddo
      enddo
   enddo
   enddo
else
   call abortdns("decay():  invalid 'rantype'")
endif
alpha=0
beta=1
do n=1,3
   write(message,*) 'solving for PSI n=',n   
   call print_message(message)
   call helmholtz_periodic_inv(PSI(1,1,1,n),work,alpha,beta)
enddo

call print_message("computing curl PSI")
if (ndim==2) then
   ! 2D case, treat PSI(:,:,:,1) = stream function, ignore other components
   Q=0
   ! u = PSI_y
   call der(PSI,Q,work2,work,DX_ONLY,2)     
   ! v = -PSI_x
   call der(PSI,Q(1,1,1,2),work2,work,DX_ONLY,1)
   Q(:,:,:,2)=-Q(:,:,:,2)
else
   call vorticity(Q,PSI,work,work2)
endif
call print_message("random initial condition complete")

end subroutine






subroutine rescale_e(Q,work,ener,enerb,enerb_target,NUMBANDS,nvec,do_rescale)
!
! rescale initial data to match spectra in enerb_target
! preserve phases of all modes
!
! if do_rescale == 0 rescaling is DISABLED
! (but we still compute "ener" and "enerb")
!
use params
use transpose
use mpi
implicit none
integer :: NUMBANDS,nvec,do_rescale
real*8 :: Q(nx,ny,nz,nvec)
real*8 :: work(nx,ny,nz)
real*8 :: enerb_target(NUMBANDS)
real*8 :: enerb(NUMBANDS)
real*8 :: enerb_work(NUMBANDS)
real*8 :: ener

integer :: n,im,jm,km,i,j,k,nb,ierr
real*8 :: xfac,xw
character(len=80) :: message

if (do_rescale==1) call print_message("Rescaling initial condition")


enerb=0
do n=1,nvec
   write(message,*) 'FFT to spectral space n=',n   
   call print_message(message)
   call fft3d(Q(1,1,1,n),work) 
   write(message,*) 'computing E(k) n=',n   
   call print_message(message)
   do k=nz1,nz2
      km=kmcord(k)
      do j=ny1,ny2
         jm=jmcord(j)
         do i=nx1,nx2
            im=imcord(i)
            xw=sqrt(real(km**2/Lz/Lz + jm**2 + im**2))

            xfac = (2*2*2)
            if (km==0) xfac=xfac/2
            if (jm==0) xfac=xfac/2
            if (im==0) xfac=xfac/2

            do nb=1,NUMBANDS
               if (xw>=nb-.5 .and. xw<nb+.5) then
                    enerb(nb)=enerb(nb)+.5*xfac*Q(i,j,k,n)**2
                    if (dealias_remove(abs(im),abs(jm),abs(km))) then
                       print *,'WARNING: adding energy to mode that will be dealiased: ',im,jm,km
                    endif
                 endif
            enddo
            !remaining coefficients to 0:
            nb=NUMBANDS+1
            if (xw>=nb-.5) then 
               Q(i,j,k,n)=0
               if (.not. dealias_remove(abs(im),abs(jm),abs(km))) then
                  ! print *,'NOTE: truncating non-dealiased mode',im,jm,km
               endif
            endif
         enddo
      enddo
   enddo
enddo

#ifdef USE_MPI
   enerb_work=enerb
   call mpi_allreduce(enerb_work,enerb,NUMBANDS,MPI_REAL8,MPI_SUM,comm_3d,ierr)
#endif


do n=1,nvec
   if (do_rescale==1) then
      write(message,*) 'normalizing to E_target(k) n=',n   
      call print_message(message)
   endif

   do k=nz1,nz2
      km=kmcord(k)
      do j=ny1,ny2
         jm=jmcord(j)
         do i=nx1,nx2
            im=imcord(i)
            xw=sqrt(real(km**2+jm**2+im**2))

            if (do_rescale==1) then
            do nb=1,NUMBANDS
            if (xw>=nb-.5 .and. xw<nb+.5) then
               Q(i,j,k,n)=Q(i,j,k,n)*sqrt(enerb_target(nb)/(enerb(nb)))
            endif
            enddo
            endif
         enddo
      enddo
   enddo
enddo



ener=0
enerb=0
do n=1,nvec
   write(message,*) 're-computing E(k) n=',n   
   call print_message(message)
   do k=nz1,nz2
      km=kmcord(k)
      do j=ny1,ny2
         jm=jmcord(j)
         do i=nx1,nx2
            im=imcord(i)
            xw=sqrt(real(km**2+jm**2+im**2))

            xfac = (2*2*2)
            if (km==0) xfac=xfac/2
            if (jm==0) xfac=xfac/2
            if (im==0) xfac=xfac/2

            do nb=1,NUMBANDS
            if (xw>=nb-.5 .and. xw<nb+.5) then
               enerb(nb)=enerb(nb)+.5*xfac*Q(i,j,k,n)**2
            endif
            enddo
            ener=ener+.5*xfac*Q(i,j,k,n)**2


         enddo
      enddo
   enddo
!   write(message,*) 'E(k) = ',enerb
!   call print_message(message)	
enddo


do n=1,nvec
   write(message,*) 'FFT back to grid space, n=',n   
   call print_message(message)
   call ifft3d(Q(1,1,1,n),work) 
enddo
#ifdef USE_MPI
   xfac=ener
   call mpi_allreduce(xfac,ener,1,MPI_REAL8,MPI_SUM,comm_3d,ierr)
   enerb_work=enerb
   call mpi_allreduce(enerb_work,enerb,NUMBANDS,MPI_REAL8,MPI_SUM,comm_3d,ierr)
#endif
end subroutine

subroutine init_tw(init,Q,Qhat,work1,work2)
!
! low wave number, quasi isotropic initial condition
!
! init=0    initialize schmidt number only
! init=1    initialize schmidt number and passive scalar data
!
!
use params
implicit none
real*8 :: Q(nx,ny,nz,n_var)
real*8 :: Qhat(nx,ny,nz,n_var)
real*8 :: work1(nx,ny,nz)
real*8 :: work2(nx,ny,nz)
real*8 :: xfac,mn,mx,ke_percent
integer :: n,k,i,j,im,jm,km,init,count,iter,n1
character(len=80) :: message


if (my_pe==io_pe) then
   print *,"Baroclinic Instability"
endif


do j=1,ny_2dz
   jm=z_jmcord(j)
   do i=1,nx_2dz
      im=z_imcord(i)
      do k=1,g_nz
         km=z_kmcord(k)
         if(im==0.and.jm==1.and.km==1) Qhat(k,i,j,1)=1
         if(im==0.and.jm==2.and.km==2) Qhat(k,i,j,4)=-bous
      enddo
   enddo
enddo

Q=Qhat
call ifft3d(Q(1,1,1,1),work1) 
call ifft3d(Q(1,1,1,4),work1) 

end subroutine init_tw

subroutine init_thrmlwnd(Q,PSI,work,work2)
use params
implicit none
real*8 :: Q(nx,ny,nz,4)
real*8 :: PSI(nx,ny,nz,4)
real*8 :: work(nx,ny,nz)
real*8 :: work2(nx,ny,nz)

! local variables
integer :: i,j,k
real*8 :: x,y,z


do k=nz1,nz2
   z=zcord(k)
   do j=ny1,ny2
      y=ycord(j)
      do i=nx1,nx2
         x=xcord(i)

         ! (x,y,z) is the coordinate of the point (i,j,k)
         ! u velocity:
         Q(i,j,k,1) =  sin(pi2*y) * sin(pi2*z)
         ! v velocity:
         Q(i,j,k,2) =  0
         ! w velocity:
         Q(i,j,k,3) =  0
         ! theta
         Q(i,j,k,4) =  -bous*cos(pi2*y) * cos(pi2*z)

      enddo
   enddo
enddo
end subroutine init_thrmlwnd
