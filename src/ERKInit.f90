!############################################################################################
!
! Copyright 2019 Bharat Mahajan
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!    http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!
!> \brief       ERK Init submodule
!! \details     It provides implementation for the init, final, and some miscellaneous methods
!!              of ERK module.
!! \author      Bharat Mahajan
!! \version     0.9
!! \date        01/25/2019    
!
!############################################################################################
    
    submodule (ERK) ERKInit

    contains
    
    module subroutine erk_init(me, DE, MaxSteps, Method, ATol, RTol,  &
        InterpOn, InterpStates, MinStepSize, MaxStepSize, StepSzParams, EventsOn, EventStepSz)
    
        implicit none
        
        class(ERK_class), intent(inout) :: me
        class(DiffEqSys), target :: DE
        integer, intent(in) :: MaxSteps        
        integer, intent(in), optional :: Method 
        real(WP), dimension(:), intent(in), optional :: ATol
        real(WP), dimension(:), intent(in), optional :: RTol            
        logical, intent(in), optional :: InterpOn
        integer, dimension(:), intent(in), optional :: InterpStates
        real(WP), intent(in), optional :: MinStepSize, MaxStepSize
        real(WP), dimension(5), intent(in), optional :: StepSzParams
        logical, intent(in), optional :: EventsOn
        real(WP), intent(in), optional :: EventStepSz        

        integer :: status
        logical :: isSacalarTol 
        real(DP) :: X        
        real(DP), dimension(2) :: Params, Y, dYdX
        
        ! assign the method
        if (present(Method)) me%Method = Method
    
        ! Pointer to the user-supplied Diff Eq system object
        me%pDiffEqSys => DE
        
        ! user must specify maximum number of steps allowed to take,
        ! we will allocate memory based on this number
        if (MaxSteps <= 0) then
            me%status = FLINT_ERROR_PARAMS
            return
        else
            me%MaxSteps = MaxSteps
        end if
        
        ! Check if tolerances are scalars or vectors?
        if (size(ATol) == 1 .AND. size(RTol) == 1) then
            me%IsScalarTol = .TRUE.
            me%ATol = ATol
            me%RTol = RTol
        else if (size(ATol) == me%pDiffEqSys%n .AND. size(RTol) == me%pDiffEqSys%n) then
            me%IsScalarTol = .FALSE.
            me%ATol = ATol
            me%RTol = RTol
        else
            me%status = FLINT_ERROR_PARAMS
            return
        end if            
            
        ! Step-size related options
        
        ! Minimum-step size: if 0 then it is equal to eps
        if (present(MinStepSize)) then
            me%MinStepSize = abs(MinStepSize)
        else
            me%MinStepSize = EPS
        end if
            
        ! Maximum-step size: if 0 then it will be set equal to Xf - X0
        if (present(MaxStepSize)) then
            me%MaxStepSize = abs(MaxStepSize)
        else
            me%MaxStepSize = 0.0_WP
        end if        

        ! method-specific tuning parameters
        if (present(StepSzParams)) then
            me%StepSzParams = StepSzParams
        else
            select case (me%method)
        
            case (ERK_DOP853,ERK_DOP54,ERK_VERNER98R, ERK_VERNER65E)
                me%StepSzParams = [SF, SFMIN, SFMAX, BETA, hbyhoptOLD]
            case default
                ! Not implemented yet
            end select
            
        end if
        
        ! If interpolation is ON?    
        ! deallocate first if already allocated
        call IntpMemDeallocate()        
        if (present(InterpOn)) then
            if (InterpOn) then
                me%InterpOn = .TRUE.
            else
                me%InterpOn = .FALSE.
            end if
        end if
        
        !> Use Events option if specified
        if (present(EventsOn)) me%EventsOn = EventsOn
        
        !> Event step size is always positive
        if (me%EventsOn .EQV. .TRUE.) then
            ! For events, we need to interpolate all the states
            me%InterpStates = [integer :: (doI,doI=1,me%pDiffEqSys%n)]

            ! make sure event step sz is always positive
            if (present(EventStepSz)) me%EventStepSz = abs(EventStepSz)
        end if
        
        ! choose method-specific parameters
        select case (me%method)
        
            case (ERK_DOP853)
                me%s = DOP853_s
                me%sint = DOP853_sint
                me%a(1:int((me%s-1)/2.0*me%s)) = DOP853_a
                me%b(1:me%s) = DOP853_b
                me%c(2:me%s) = DOP853_c
                me%e(1:me%sint) = DOP853_e
                me%IsFSALMethod = DOP853_FSAL

                if (me%InterpOn .OR. me%EventsOn) then
                    me%pstar = DOP853_pstar
                    me%dinz(1:size(DOP853_di_NZ)+1) = [DOP853_di_NZ, -1]
                    me%d(1:size(DOP853_di_NZ),1:size(DOP853_dj_NZ)) = DOP853_d
                end if
                
            case (ERK_VERNER98R)
                me%s = Verner98R_s
                me%sint = Verner98R_sint
                me%a(1:int((me%s-1)/2.0*me%s)) = Verner98R_a
                me%b(1:me%s) = Verner98R_b
                me%c(2:me%s) = Verner98R_c
                me%e(1:me%sint) = Verner98R_e
                me%IsFSALMethod = Verner98R_FSAL                
            
                if (me%InterpOn .OR. me%EventsOn) then
                    me%pstar = Verner98R_pstar
                    me%dinz(1:size(Verner98R_di_NZ)+1) = [Verner98R_di_NZ, -1]
                    me%d(1:size(Verner98R_di_NZ),1:Verner98R_pstar) = Verner98R_d
                end if
                
            case (ERK_VERNER65E)
                me%s = Verner65E_s
                me%sint = Verner65E_sint
                me%a(1:int((me%s-1)/2.0*me%s)) = Verner65E_a
                me%b(1:me%s) = Verner65E_b
                me%c(2:me%s) = Verner65E_c
                me%e(1:me%sint) = Verner65E_e
                me%IsFSALMethod = Verner65E_FSAL                
            
                if (me%InterpOn .OR. me%EventsOn) then
                    me%pstar = Verner65E_pstar
                    me%dinz(1:size(Verner65E_di_NZ)+1) = [Verner65E_di_NZ, -1]
                    me%d(1:size(Verner65E_di_NZ),1:Verner65E_pstar) = Verner65E_d
                end if                

            case (ERK_DOP54)
                me%s = DOP54_s
                me%sint = DOP54_sint
                me%a(1:int((me%s-1)/2.0*me%s)) = DOP54_a
                me%b(1:me%s) = DOP54_b
                me%c(2:me%s) = DOP54_c
                me%e(1:me%sint) = DOP54_e
                me%IsFSALMethod = DOP54_FSAL                
            
                if (me%InterpOn .OR. me%EventsOn) then
                    me%pstar = DOP54_pstar
                    me%dinz(1:size(DOP54_di_NZ)+1) = [DOP54_di_NZ, -1]
                    me%d(1:size(DOP54_di_NZ),1:2) = DOP54_d
                end if                
                
            case default
                ! We will never be friends, so why are you here?
        end select

        !> \remark Things to do if Interpolation is needed: 
        !! + Choose number of ERK stages
        !! + Allocate memeory for internal state: allocate now using max number of
        !! steps allowed to take. This is to avoid heap allocation on every call
        !! to Intgerate.
        if (me%InterpOn) then
            ! check if dense output states are specified, else use all
            ! If events are enabled, we save the coefficients for dense output for all states by default
            me%status = FLINT_SUCCESS
            if (present(InterpStates)) then
                ! check for valid components
                if (size(InterpStates) < 1 .OR. size(InterpStates) > me%pDiffEqSys%n &
                    .OR. any(InterpStates < 1) .OR. any(InterpStates > me%pDiffEqSys%n)) then
                    me%status = FLINT_ERROR_INTPSTATES
                else
                    me%InterpStates = InterpStates
                    me%status = FLINT_SUCCESS                            
                end if
            else
                ! use all states for dense output
                me%InterpStates = [integer :: (doI,doI=1,me%pDiffEqSys%n)]
                me%status = FLINT_SUCCESS
            end if
                
            if (me%status /= FLINT_SUCCESS) return

            ! Now allocate storage for internal steps as well as interpolation coefficients
            call IntpMemAllocate()         
       
            if (me%status /= FLINT_SUCCESS) return                
        end if
        
    contains
    
    subroutine IntpMemAllocate()

        allocate(me%Xint(me%MaxSteps), stat=status)
        if (status /= 0) me%status = FLINT_ERROR_MEMALLOC
        
        !allocate(me%Yint(DE%n, me%MaxSteps), stat=status)
        !if (status /= 0) me%status = FLINT_ERROR_MEMALLOC
        
        allocate(me%Bip(size(me%InterpStates), 0:me%pstar, me%MaxSteps), stat=status)
        if (status /= 0) me%status = FLINT_ERROR_MEMALLOC
    
    end subroutine
        
    subroutine IntpMemDeallocate()
    
        if (allocated(me%Xint)) deallocate(me%Xint, stat = status)
        !if (allocated(me%Yint)) deallocate(me%Yint, stat = status)                  
        if (allocated(me%Bip)) deallocate(me%Bip, stat = status)                  
    
    end subroutine
        
    end subroutine erk_init
    
    
    
    module subroutine erk_info(me, LastStatus, nSteps, nAccept, nReject, nFCalls, &
                                InterpReady, h0, X0, Y0, hf, Xf, Yf)

            !import :: FLINT_class, WP
        
            class(ERK_class), intent(inout) :: me
            integer(kind(FLINT_SUCCESS)), intent(out) :: LastStatus
            integer, intent(out), optional :: nSteps
            integer, intent(out), optional :: nAccept
            integer, intent(out), optional :: nReject
            integer, intent(out), optional :: nFCalls
            logical, intent(out), optional :: InterpReady
            real(WP), intent(out), optional :: h0
            real(WP), intent(out), optional :: X0
            real(WP), dimension(:), intent(out), optional :: Y0
            real(WP), intent(out), optional :: hf
            real(WP), intent(out), optional :: Xf
            real(WP), dimension(:), intent(out), optional :: Yf
            
            
            ! return last status of the integration
            LastStatus = me%status
            
            ! optional information starts here
            
            if (present(nSteps)) nSteps = me%TotalSteps
            
            if (present(nAccept)) nAccept = me%AcceptedSteps
            
            if (present(nReject)) nReject = me%RejectedSteps
            
            if (present(nFCalls)) nFCalls = me%FCalls
            
            if (present(InterpReady)) InterpReady = me%InterpOn
            
            if (present(h0)) X0 = me%h0
            if (present(X0)) X0 = me%X0
            if (present(Y0)) Y0 = me%Y0
            if (present(hf)) X0 = me%hf
            if (present(Xf)) X0 = me%Xf
            if (present(Yf)) Y0 = me%Yf
            
    end subroutine erk_info
    
    
    
    
    
    
    !> Destructor routine deallocates all the allocatable data structure
    module subroutine erk_destroy(me)
    
        type(ERK_class) :: me
        
        ! deallocate memory
        if (allocated(me%Atol)) deallocate(me%ATol)
        if (allocated(me%Rtol)) deallocate(me%RTol)
        if (allocated(me%InterpStates)) deallocate(me%InterpStates)
        if (allocated(me%Xint)) deallocate(me%Xint)
        !if (allocated(me%Yint)) deallocate(me%Yint)                  
        if (allocated(me%Bip)) deallocate(me%Bip)                  
        if (allocated(me%Y0)) deallocate(me%Y0)                  
        if (allocated(me%Yf)) deallocate(me%Yf)                  
        
    end subroutine erk_destroy    
    
end submodule ERKInit