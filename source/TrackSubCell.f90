module TrackSubCellModule
  use ParticleLocationModule,only : ParticleLocationType
  use TrackSubCellResultModule,only : TrackSubCellResultType
  use ModpathSubCellDataModule,only : ModpathSubCellDataType

  ! RWPT 
  use ParticleTrackingOptionsModule,only : ParticleTrackingOptionsType
  use ModpathCellDataModule,only : ModpathCellDataType
  use omp_lib ! mainly debugging
  implicit none
  
! Set default access status to private
  private

  type,public :: TrackSubCellType
    type(ModpathSubCellDataType) :: SubCellData

    ! RWPT
    ! qx, qy, qz, qnorm
    doubleprecision, dimension(4) :: qCorner000
    doubleprecision, dimension(4) :: qCorner100
    doubleprecision, dimension(4) :: qCorner010
    doubleprecision, dimension(4) :: qCorner110
    doubleprecision, dimension(4) :: qCorner001
    doubleprecision, dimension(4) :: qCorner101
    doubleprecision, dimension(4) :: qCorner011
    doubleprecision, dimension(4) :: qCorner111

    ! corner porosities
    doubleprecision :: porosity000
    doubleprecision :: porosity100
    doubleprecision :: porosity010
    doubleprecision :: porosity110
    doubleprecision :: porosity001
    doubleprecision :: porosity101
    doubleprecision :: porosity011
    doubleprecision :: porosity111

    ! Interpolation indexes !
    ! Corner discharge components indexes
    ! 8 corners, 3 subcell indexes, 1 face id
    integer, dimension(8,4) :: cornerXComponentIndexes, &
                               cornerYComponentIndexes, & 
                               cornerZComponentIndexes
    ! Corner porosity sub cell indexes
    integer, dimension(8,6)  :: cornerPorosityIndexes ! 8 corners, 6 neighbor subcells

    ! RWPT Pointers
    procedure(Advection), pass, pointer :: AdvectionDisplacement=>null()
    procedure(ExitFaceAndTimeStep), pass, pointer :: ExitFaceAndUpdateTimeStep=>null()
    procedure(DispersionModel), pass, pointer :: ComputeRWPTDisplacements=>null()
    procedure(RandomDisplacement), pass, pointer :: DisplacementRandomDischarge=>null()

    ! Needed for OBS (?)
    type(TrackSubCellResultType) :: TrackSubCellResult

    ! Flags to indicate whether or not 
    ! to consider random motion ( to be deprecated ) 
    logical :: moveX = .true.
    logical :: moveY = .true.
    logical :: moveZ = .true.

    ! Point towards trackingOptions
    integer, dimension(:), pointer :: dimensions
    integer, pointer :: nDim

  contains
    procedure,private :: CalculateDT=>pr_CalculateDT
    procedure,private :: NewXYZ=>pr_NewXYZ
    procedure :: ExecuteTracking=>pr_ExecuteTracking

    ! RWPT
    procedure :: InitializeRandomWalk=>pr_InitializeRandomWalk
    procedure :: ExecuteRandomWalkParticleTracking=>pr_ExecuteRandomWalkParticleTracking
    procedure :: LinearInterpolationVelocities=>pr_LinearInterpolationVelocities
    procedure :: ComputeRandomWalkTimeStep=>pr_ComputeRandomWalkTimeStep
    procedure :: ComputeCornerVariables=>pr_ComputeCornerVariables
    procedure :: ComputeCornerDischarge=>pr_ComputeCornerDischarge
    procedure :: GetInterpolatedCornerDischarge=>pr_GetInterpolatedCornerDischarge
    procedure :: SetCornerComponentsIndexes=>pr_SetCornerComponentsIndexes
    procedure :: ComputeCornerPorosity=> pr_ComputeCornerPorosity
    procedure :: GetInterpolatedCornerPorosity=>pr_GetInterpolatedCornerPorosity
    procedure :: SetCornerPorosityIndexes=> pr_SetCornerPorosityIndexes
    procedure :: Trilinear=>pr_Trilinear
    procedure :: TrilinearDerivative=>pr_TrilinearDerivative
    procedure :: SetDispersionDisplacement=>pr_SetDispersionDisplacement
    procedure :: DispersionDivergenceDischarge=>pr_DispersionDivergenceDischarge
    !procedure :: DisplacementRandomDischarge=>pr_DisplacementRandomDischarge1D
    !procedure :: DisplacementRandomDischarge=>pr_DisplacementRandomDischarge2D
    !procedure :: DisplacementRandomDischarge=>pr_DisplacementRandomDischarge
    procedure :: GenerateStandardNormalRandom=>pr_GenerateStandardNormalRandom
    procedure :: AdvectionDisplacementExponential=>pr_AdvectionDisplacementExponential
    procedure :: AdvectionDisplacementEulerian=>pr_AdvectionDisplacementEulerian
    procedure :: NewtonRaphsonTimeStep=>NewtonRaphsonTimeStepExponentialAdvection

  end type


  ! RWPT
  ! Interfaces
  abstract interface

      ! Advection model
      subroutine Advection( this, x, y, z, dt, vx, vy, vz, &
                            dAdvx, dAdvy, dAdvz )
          import TrackSubCellType
          ! this
          class(TrackSubCellType) :: this 
          !input
          doubleprecision, intent(in) :: x, y, z, dt
          doubleprecision, intent(in) :: vx, vy, vz
          ! output
          doubleprecision, intent(inout) :: dAdvx, dAdvy, dAdvz
      end subroutine Advection

      ! Update time step model,
      ! determined by advection model
      subroutine ExitFaceAndTimeStep( this, x, y, z, nx, ny, nz, & 
                 vx, vy, vz, divDx, divDy, divDz, dBx, dBy, dBz, &
                 t, dt, dtxyz, exitFace )
          import TrackSubCellType
          ! this
          class(TrackSubCellType) :: this 
          ! input
          doubleprecision, intent(in) :: x, y, z
          doubleprecision, intent(in) :: nx, ny, nz
          doubleprecision, intent(in) :: vx, vy, vz
          doubleprecision, intent(in) :: divDx, divDy, divDz
          doubleprecision, intent(in) :: dBx, dBy, dBz
          ! output
          doubleprecision, intent(inout) :: t, dt
          integer, intent(inout)         :: exitFace
          doubleprecision, dimension(3), intent(inout) :: dtxyz
      end subroutine ExitFaceAndTimeStep

      ! Dispersion model 
      ! Interfaces between linear and nonlinear dispersion
      subroutine DispersionModel( this, x, y, z, vx, vy, vz, &
                                       dt, trackingOptions, &
                                       dAdvx, dAdvy, dAdvz, &
                                             dBx, dBy, dBz, &
                                       divDx, divDy, divDz  )
          import TrackSubCellType
          import ParticleTrackingOptionsType
          ! this
          class(TrackSubCellType) :: this
          ! input
          type(ParticleTrackingOptionsType),intent(in) :: trackingOptions
          doubleprecision, intent(in)    :: x, y, z, dt
          ! output
          doubleprecision, intent(inout) :: vx, vy, vz 
          doubleprecision, intent(inout) :: dAdvx, dAdvy, dAdvz 
          doubleprecision, intent(inout) :: dBx, dBy, dBz 
          doubleprecision, intent(inout) :: divDx, divDy, divDz  
      end subroutine DispersionModel 

      ! Random displacement function
      ! Determined by dimensions 
      subroutine RandomDisplacement( this, x, y, z, alphaL, alphaT, &
                                               dMEff, dBx, dBy, dBz )
          import TrackSubCellType
          class (TrackSubCellType) :: this
          ! input
          doubleprecision, intent(in)    :: x, y, z
          doubleprecision, intent(in)    :: alphaL, alphaT, dMEff
          ! output
          doubleprecision, intent(out) :: dBx, dBy, dBz
      end subroutine RandomDisplacement


  end interface


contains

  subroutine pr_ExecuteTracking(this,stopIfNoExit,initialLocation,maximumTime, trackingResult)
  !-------------------------------------------------------------------
  !
  !-------------------------------------------------------------------
  ! Specifications
  !-------------------------------------------------------------------
  implicit none
  class(TrackSubCellType) :: this
  logical,intent(in) :: stopIfNoExit
  type(ParticleLocationType),intent(in) :: initialLocation
  doubleprecision,intent(in) :: maximumTime
  type(TrackSubCellResultType),intent(inout) :: trackingResult
  integer :: cellNumber
  doubleprecision :: initialX,initialY,initialZ,initialTime
  doubleprecision :: vx1,vx2,vy1,vy2,vz1,vz2
  doubleprecision :: vx,dvxdx,dtx,vy,dvydy,dty,vz,dvzdz,dtz,dt
  doubleprecision :: t,x,y,z
  integer :: exitFace
  integer :: statusVX,statusVY,statusVZ
  !-------------------------------------------------------------------

  call trackingResult%Reset()
  
  cellNumber = initialLocation%CellNumber
  initialX = initialLocation%LocalX
  initialY = initialLocation%LocalY
  initialZ = initialLocation%LocalZ
  initialTime = initialLocation%TrackingTime
  
  trackingResult%CellNumber = cellNumber
  trackingResult%Row = this%SubCellData%Row
  trackingResult%Column = this%SubCellData%Column
  trackingResult%InitialLocation%CellNumber = cellNumber
  trackingResult%InitialLocation%LocalX = initialX
  trackingResult%InitialLocation%LocalY = initialY
  trackingResult%InitialLocation%LocalZ = initialZ
  trackingResult%InitialLocation%TrackingTime = initialTime
  trackingResult%FinalLocation%LocalX = initialX
  trackingResult%FinalLocation%LocalY = initialY
  trackingResult%FinalLocation%LocalZ = initialZ
  trackingResult%FinalLocation%TrackingTime = initialTime
  trackingResult%MaximumTime = maximumTime
  trackingResult%Status = trackingResult%Status_Undefined()
  
  if(stopIfNoExit) then
    if(.not. this%SubCellData%HasExitFace()) then
      trackingResult%Status = trackingResult%Status_NoExitPossible()
      return
    end if
  end if
  
  ! Make local copies of face velocities for convenience
  vx1 = this%SubCellData%VX1
  vx2 = this%SubCellData%VX2
  vy1 = this%SubCellData%VY1
  vy2 = this%SubCellData%VY2
  vz1 = this%SubCellData%VZ1
  vz2 = this%SubCellData%VZ2

  ! Compute time of travel to each possible exit face
  statusVX = this%CalculateDT(vx1, vx2, this%SubCellData%DX, initialX, vx, dvxdx, dtx)
  statusVY = this%CalculateDT(vy1, vy2, this%SubCellData%DY, initialY, vy, dvydy, dty)
  statusVZ = this%CalculateDT(vz1, vz2, this%SubCellData%DZ, initialZ, vz, dvzdz, dtz)

  ! This snippet selects dt and determines the exitFace
  exitFace = 0
  dt = 1.0d+30
  if((statusVX .lt. 2) .or. (statusVY .lt. 2) .or. (statusVZ .lt. 2)) then
    dt = dtx
    if(vx .lt. 0d0) then
      exitFace = 1
    else if(vx .gt. 0) then
      exitFace = 2
    end if
    
    if(dty .lt. dt) then
      dt = dty
      if(vy .lt. 0d0) then
        exitFace = 3
      else if(vy .gt. 0d0) then
        exitFace = 4
      end if
    end if
    
    if(dtz .lt. dt) then
      dt = dtz
      if(vz .lt. 0d0) then
        exitFace = 5
      else if(vz .gt. 0d0) then
        exitFace = 6
      end if
    end if
  else
  end if

  ! Increment t
  t = initialTime + dt
  
  ! If the maximum time is less than the computed exit time, then calculate the
  ! particle location at the maximum time and set the final time equal to
  ! the maximum time. Set status to 2 (MaximumTimeReached) and return.
  if(maximumTime .lt. t) then
    dt = maximumTime - initialTime
    t = maximumTime
    x = this%NewXYZ(vx, dvxdx, vx1, vx2, dt, initialX, this%SubCellData%DX, statusVX)
    y = this%NewXYZ(vy, dvydy, vy1, vy2, dt, initialY, this%SubCellData%DY, statusVY)
    z = this%NewXYZ(vz, dvzdz, vz1, vz2, dt, initialZ, this%SubCellData%DZ, statusVZ)
    trackingResult%ExitFace = 0
    trackingResult%FinalLocation%CellNumber = cellNumber
    trackingResult%FinalLocation%LocalX = x
    trackingResult%FinalLocation%LocalY = y
    trackingResult%FinalLocation%LocalZ = z
    trackingResult%FinalLocation%TrackingTime = t
    trackingResult%Status = trackingResult%Status_ReachedMaximumTime()
  else
      ! Otherwise, if the computed exit time is less than or equal to the maximum time,
      ! then calculate the exit location and set the final time equal to the computed
      ! exit time.
      if((exitFace .eq. 1) .or. (exitFace .eq.2)) then
          x = 0d0
          y = this%NewXYZ(vy, dvydy, vy1, vy2, dt, initialY, this%SubCellData%DY, statusVY)
          z = this%NewXYZ(vz, dvzdz, vz1, vz2, dt, initialZ, this%SubCellData%DZ, statusVZ)
          if(exitFace .eq. 2) x = 1.0d0
      else if((exitFace .eq. 3) .or. (exitFace .eq.4)) then
          x = this%NewXYZ(vx, dvxdx, vx1, vx2, dt, initialX, this%SubCellData%DX, statusVX)
          y = 0d0
          z = this%NewXYZ(vz, dvzdz, vz1, vz2, dt, initialZ, this%SubCellData%DZ, statusVZ)
          if(exitFace .eq. 4) y = 1.0d0
      else if((exitFace .eq. 5) .or. (exitFace .eq.6)) then
          x = this%NewXYZ(vx, dvxdx, vx1, vx2, dt, initialX, this%SubCellData%DX, statusVX)
          y = this%NewXYZ(vy, dvydy, vy1, vy2, dt, initialY, this%SubCellData%DY, statusVY)
          z = 0d0
          if(exitFace .eq. 6) z = 1.0d0
      else
          ! If it gets this far, something went wrong. Signal an error condition by
          ! setting Status = 0 (undefined) and then return.
          trackingResult%ExitFace = exitFace
          trackingResult%Status = trackingResult%Status_Undefined()
          return
      end if
      
      ! Assign tracking result data
      trackingResult%ExitFaceConnection = this%SubCellData%Connection(exitFace)
      if(this%SubCellData%Connection(exitFace) .lt. 0) then
          trackingResult%Status = trackingResult%Status_ExitAtInternalFace()
      else
          trackingResult%Status = trackingResult%Status_ExitAtCellFace()
      end if
      trackingResult%ExitFace = exitFace
      trackingResult%FinalLocation%CellNumber = cellNumber
      trackingResult%FinalLocation%LocalX = x
      trackingResult%FinalLocation%LocalY = y
      trackingResult%FinalLocation%LocalZ = z
      trackingResult%FinalLocation%TrackingTime = t
  end if

  end subroutine pr_ExecuteTracking
  
!-------------------------------------------------------------------
  function pr_CalculateDT(this,v1,v2,dx,xL,v,dvdx,dt) result(status)
  implicit none
  class(TrackSubCellType) :: this
  doubleprecision,intent(in) :: v1,v2,dx,xL
  doubleprecision,intent(inout) :: v,dvdx,dt
  doubleprecision :: v2a,v1a,dv,dva,vv,vvv,zro,zrom,x,tol
  doubleprecision :: vr1,vr2,vr,v1v2
  integer :: status
  logical :: noOutflow
  
  ! Initialize variables
  status = -1
  dt = 1.0d+20
  v2a = v2
  if(v2a .lt. 0d0) v2a = -v2a
  v1a = v1
  if(v1a .lt. 0d0) v1a = -v1a
  dv = v2 - v1
  dva = dv
  if(dva .lt. 0d0) dva = -dva
  
  ! Check for a uniform zero velocity in this direction.
  ! If so, set status = 2 and return (dt = 1.0d+20).
  tol = 1.0d-15
  if((v2a .lt. tol) .and. (v1a .lt. tol)) then
    v = 0d0
    dvdx = 0d0
    status = 2
    return
  end if
  
  ! Check for uniform non-zero velocity in this direction. 
  ! If so, set compute dt using the constant velocity, 
  ! set status = 1 and return.
  vv = v1a
  if(v2a .gt. vv) vv = v2a
  vvv = dva / vv
  if(vvv .lt. 1.0d-4) then
    zro = tol
    zrom = -zro
    v = v1
    x = xL * dx
    if(v1 .gt. zro) dt = (dx - x) / v1
    if(v1 .lt. zrom) dt = -x / v1
    dvdx = 0d0
    status = 1
    return
  end if
  
  ! Velocity has a linear variation.
  ! Compute velocity corresponding to particle position
  dvdx = dv / dx
  v = (1.0d0 - xL)*v1 + xL*v2
  
  ! If flow is into the cell from both sides there is no outflow.
  ! In that case, set status = 3 and return
  noOutflow = .true.
  if(v1 .lt. 0d0) noOutflow = .false.
  if(v2 .gt. 0d0) noOutflow = .false.
  if(noOutflow) then
    status = 3
    return
  end if
  
  ! If there is a divide in the cell for this flow direction, check to see if the
  ! particle is located exactly on the divide. If it is, move it very slightly to
  ! get it off the divide. This avoids possible numerical problems related to 
  ! stagnation points.
  if((v1 .le. 0d0) .and. (v2 .ge. 0d0)) then
    if(abs(v)  .le. 0d0) then
      v = 1.0d-20
      if(v2 .le. 0d0) v = -v
    end if
  end if

  ! If there is a flow divide, this check finds out what side of the divide the particle
  ! is on and sets the value of vr appropriately to reflect that location.
  vr1 = v1 / v
  vr2 = v2 / v
  vr = vr1
  if(vr .le. 0d0) vr = vr2
  
  ! Check to see if the velocity is in the same direction throughout the cell (i.e. no flow divide).
  ! Check to see if the product v1*v2 > 0 then the velocity is in the same direction throughout 
  ! the cell (i.e. no flow divide). If so, set the value of vr to reflect the appropriate direction.
  v1v2 = v1*v2
  if(v1v2 .gt. 0d0) then
    if(v .gt. 0d0) vr = vr2
    if(v .lt. 0d0) vr = vr1
  end if
  
  ! Compute travel time to exit face. Return with status = 0
  dt = log(vr) / dvdx
  status = 0
    
  end function pr_CalculateDT
  
!-------------------------------------------------------------------
  function pr_NewXYZ(this,v,dvdx,v1,v2,dt,x,dx,velocityProfileStatus) result(newX)
  implicit none
  class(TrackSubCellType) :: this
  integer,intent(in) :: velocityProfileStatus
  doubleprecision,intent(in) :: v,dvdx,v1,v2,dt,x,dx
  doubleprecision :: newX

  newX = x
  select case (velocityProfileStatus)
    case (1)
      newX = newX + (v1*dt/dx)
    case default
      if(v .ne. 0d0) then
        newX = newX + (v*(exp(dvdx*dt) - 1.0d0)/dvdx/dx)
      end if
  end select
  if(newX .lt. 0d0) newX = 0d0
  if(newX .gt. 1.0d0) newX = 1.0d0
  
  end function pr_NewXYZ


! RWPT
!-------------------------------------------------------------------
  subroutine pr_InitializeRandomWalk(this, trackingOptions)
      !------------------------------------------------------------
      ! Called in trackingEngine%Initialize
      !------------------------------------------------------------
      ! Specifications
      !------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this
      type(ParticleTrackingOptionsType),intent(in), target :: trackingOptions
      !------------------------------------------------------------

      ! Assign displacement pointers
      if ( trackingOptions%advectionKind .eq. 1 ) then 
          this%AdvectionDisplacement=>pr_AdvectionDisplacementExponential
          this%ExitFaceAndUpdateTimeStep=>pr_DetectExitFaceAndUpdateTimeStepNewton
      else if ( trackingOptions%advectionKind .eq. 2 ) then 
          this%AdvectionDisplacement=>pr_AdvectionDisplacementEulerian
          this%ExitFaceAndUpdateTimeStep=>pr_DetectExitFaceAndUpdateTimeStepQuadratic
      end if

      ! Set indexes for corner x,y,z components
      call this%SetCornerComponentsIndexes() 

      ! Set indexes for corner porosities
      call this%SetCornerPorosityIndexes()

      ! Dispersion displacement function is set in particletrackingengine
      !call this%SetDispersionDisplacement( trackingOptions%dispersionModel )

      ! Initialize random displacement flags ( to be deprecated )
      if ( trackingOptions%dimensionMask(1) .eq. 0 ) this%moveX = .false.
      if ( trackingOptions%dimensionMask(2) .eq. 0 ) this%moveY = .false.
      if ( trackingOptions%dimensionMask(3) .eq. 0 ) this%moveZ = .false.

      this%dimensions => trackingOptions%dimensions
      this%nDim => trackingOptions%nDim
      
      ! Assign random displacement function
      select case(this%nDim) 
        case(1)
          this%DisplacementRandomDischarge => pr_DisplacementRandomDischarge1D
        case(2)
          this%DisplacementRandomDischarge => pr_DisplacementRandomDischarge2D
        case(3)
          this%DisplacementRandomDischarge => pr_DisplacementRandomDischarge
      end select


      ! Done
      return


  end subroutine pr_InitializeRandomWalk


  subroutine pr_SetDispersionDisplacement(this, dispersionModel)
      !------------------------------------------------------------
      !
      !------------------------------------------------------------
      ! Specifications
      !------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this
      integer :: dispersionModel 
      !------------------------------------------------------------

      ! Assign displacement pointers
      if ( dispersionModel .eq. 1 ) then 
       !  Linear
       this%ComputeRWPTDisplacements => pr_RWPTDisplacementsLinear 
      !else if ( dispersionModel .eq.2 ) then
      ! ! Non linear 
      ! this%ComputeRWPTDisplacements => pr_RWPTDisplacementsNonlinear
      else 
       ! Not set !
       ! Some kind of error handling
       write(*,*) 'TrackSubCell:SetDispersionDisplacement: dispersionModel ' , dispersionModel ,' NOT implemented. Stop.'
       stop
      end if

      ! Done
      return


  end subroutine pr_SetDispersionDisplacement


  subroutine pr_RWPTDisplacementsLinear(this, x, y, z, vx, vy, vz, &
                                              dt, trackingOptions, &
                                              dAdvx, dAdvy, dAdvz, &
                                                    dBx, dBy, dBz, &
                                              divDx, divDy, divDz  )
      !------------------------------------------------------------
      !------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this
      type(ParticleTrackingOptionsType),intent(in) :: trackingOptions
      doubleprecision, intent(in)    :: x, y, z, dt
      doubleprecision, intent(inout) :: vx, vy, vz 
      doubleprecision, intent(inout) :: dAdvx, dAdvy, dAdvz 
      doubleprecision, intent(inout) :: dBx, dBy, dBz 
      doubleprecision, intent(inout) :: divDx, divDy, divDz  
      ! local
      doubleprecision :: alphaL, alphaT, dMEff
      !------------------------------------------------------------
      ! Specifications
      !------------------------------------------------------------

      dMEff    = this%SubCellData%dMEff 
      alphaL   = this%SubCellData%alphaL
      alphaT   = this%SubCellData%alphaT

      call this%LinearInterpolationVelocities( x, y, z, vx, vy, vz )
      call this%DispersionDivergenceDischarge( x, y, z, alphaL, alphaT, dMEff, divDx, divDy, divDz )
      call this%DisplacementRandomDischarge( x, y, z, alphaL, alphaT, dMEff, dBx, dBy, dBz )
      call this%AdvectionDisplacement( x, y, z, dt, vx, vy, vz, dAdvx, dAdvy, dAdvz )

      return


  end subroutine pr_RWPTDisplacementsLinear


  subroutine pr_RWPTDisplacementsNonlinear(this, x, y, z, vx, vy, vz, &
                                                 dt, trackingOptions, &
                                                 dAdvx, dAdvy, dAdvz, &
                                                       dBx, dBy, dBz, &
                                                 divDx, divDy, divDz  )
      !------------------------------------------------------------
      !------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this
      type(ParticleTrackingOptionsType),intent(in) :: trackingOptions
      doubleprecision, intent(in)    :: x, y, z, dt
      doubleprecision, intent(inout) :: vx, vy, vz 
      doubleprecision, intent(inout) :: dAdvx, dAdvy, dAdvz 
      doubleprecision, intent(inout) :: dBx, dBy, dBz 
      doubleprecision, intent(inout) :: divDx, divDy, divDz  
      ! local
      doubleprecision :: Daqueous, Dmol, betaL, betaT
      doubleprecision :: mediumDistance, mediumDelta
      doubleprecision :: alphaL, alphaT
      !------------------------------------------------------------
      ! Specifications
      !------------------------------------------------------------
        
      ! Will consider by convention that molecular diffusion 
      ! specified at configuration file is the aqueous

      ! THIS IS TEMPORARY:
      Daqueous       = trackingOptions%Dmol 
      Dmol           = Daqueous*this%SubCellData%Porosity ! Pore diffusion approx Daq*phi
      mediumDistance = trackingOptions%mediumDistance
      mediumDelta    = trackingOptions%mediumDelta
      betaL          = trackingOptions%betaLong 
      betaT          = trackingOptions%betaTrans


      alphaL = 0d0
      alphaT = 0d0


      ! NONLINEAR DISPERSION
      call this%LinearInterpolationVelocities( x, y, z, vx, vy, vz )
      ! COMPUTE DISPERSIVITIES
      call pr_ComputeNonlinearDispersivities( this, vx, vy, vz, Daqueous, &
                mediumDistance, mediumDelta, betaL, betaT, alphaL, alphaT )
      call this%DispersionDivergenceDischarge( x, y, z, alphaL, alphaT, Dmol, divDx, divDy, divDz )
      call this%DisplacementRandomDischarge( x, y, z, alphaL, alphaT, Dmol, dBx, dBy, dBz )
      call this%AdvectionDisplacement( x, y, z, dt, vx, vy, vz, dAdvx, dAdvy, dAdvz )


      return


  end subroutine pr_RWPTDisplacementsNonlinear



!-------------------------------------------------------------------
  subroutine pr_ExecuteRandomWalkParticleTracking(this,stopIfNoExit, &
          initialLocation,maximumTime,trackingResult,trackingOptions)
      !------------------------------------------------------------
      ! Function moves particles following RWPT protocol.
      ! It has been adapted from ExecuteTracking but logic
      ! differs significantly as particles are moved numerically 
      ! instead of semi-analytically
      !------------------------------------------------------------
      ! Specifications
      !------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this
      logical,intent(in) :: stopIfNoExit
      type(ParticleLocationType),intent(in) :: initialLocation
      doubleprecision,intent(in) :: maximumTime
      type(TrackSubCellResultType),intent(inout) :: trackingResult
      integer :: cellNumber
      doubleprecision :: initialX,initialY,initialZ,initialTime
      doubleprecision :: vx,vy,vz,dt
      doubleprecision :: t,x,y,z
      integer :: exitFace
      ! RWPT
      type(ParticleTrackingOptionsType),intent(in) :: trackingOptions
      doubleprecision :: divDx, divDy, divDz
      doubleprecision :: dAdvx, dAdvy, dAdvz
      doubleprecision :: dBx, dBy, dBz
      doubleprecision :: dx, dy, dz
      doubleprecision :: nx, ny, nz
      doubleprecision :: xi, yi, zi
      doubleprecision :: dxrw, dyrw, dzrw
      logical         :: continueTimeLoop
      logical         :: reachedMaximumTime
      doubleprecision :: dtold
      doubleprecision, dimension(3) :: dtxyz
      integer :: dtLoopCounter, posRestartCounter
      integer :: reboundCounter, intLoopCounter
      !------------------------------------------------------------

      ! Initialize trackingResult
      call trackingResult%Reset()
      
      cellNumber = initialLocation%CellNumber
      initialX = initialLocation%LocalX
      initialY = initialLocation%LocalY
      initialZ = initialLocation%LocalZ
      initialTime = initialLocation%TrackingTime
      
      trackingResult%CellNumber = cellNumber
      trackingResult%Row = this%SubCellData%Row
      trackingResult%Column = this%SubCellData%Column
      trackingResult%InitialLocation%CellNumber = cellNumber
      trackingResult%InitialLocation%LocalX = initialX
      trackingResult%InitialLocation%LocalY = initialY
      trackingResult%InitialLocation%LocalZ = initialZ
      trackingResult%InitialLocation%TrackingTime = initialTime
      trackingResult%FinalLocation%LocalX = initialX
      trackingResult%FinalLocation%LocalY = initialY
      trackingResult%FinalLocation%LocalZ = initialZ
      trackingResult%FinalLocation%TrackingTime = initialTime
      trackingResult%MaximumTime = maximumTime
      trackingResult%Status = trackingResult%Status_Undefined()
      
      if(stopIfNoExit) then
        if(.not. this%SubCellData%HasExitFace()) then
          trackingResult%Status = trackingResult%Status_NoExitPossible()
          return
        end if
      end if

      ! Advection model pointers are assigned in InitializeRandomWalk 
      ! called at initialize tracking engine
    
      ! Local copies of cell size
      dx = this%SubCellData%DX
      dy = this%SubCellData%DY
      dz = this%SubCellData%DZ

      ! Initialize positions
      x  = initialLocation%LocalX
      y  = initialLocation%LocalY
      z  = initialLocation%LocalZ
      nx = initialLocation%LocalX
      ny = initialLocation%LocalY
      nz = initialLocation%LocalZ


      if ( this%SubCellData%dry ) then
        ! If cell is completely dry, then particle is not displaced
        ! Q:
        ! If particle is set to InactiveCell, 
        ! can be displaced in a later cycle if cell is rewetted ?
        ! A: 
        ! in MPath7.f90 there is a verification. If cell 
        ! is partially dry, particle status is set to active for 
        ! retracking
        trackingResult%Status = trackingResult%Status_InactiveCell()
        trackingResult%FinalLocation%CellNumber = cellNumber
        trackingResult%FinalLocation%LocalX = x
        trackingResult%FinalLocation%LocalY = y
        trackingResult%FinalLocation%LocalZ = z
        trackingResult%FinalLocation%TrackingTime = t
        return
      end if 

      ! In case somehing needs to be done 
      ! for partially dry cells
      if ( this%SubCellData%partiallyDry ) then
        continue
      end if 

      ! Initialize displacements
      dxrw = 0d0
      dyrw = 0d0
      dzrw = 0d0

      ! Compute time step for RWPT
      call this%ComputeRandomWalkTimeStep( trackingOptions, dt )

      ! Initializes current time
      t     = initialTime
      dtold = dt

      ! Something wrong, leave
      if ( dt .le. 0d0 ) then 
        trackingResult%ExitFace = exitFace
        trackingResult%Status = trackingResult%Status_Undefined()
        trackingResult%FinalLocation%CellNumber = cellNumber
        trackingResult%FinalLocation%LocalX = x
        trackingResult%FinalLocation%LocalY = y
        trackingResult%FinalLocation%LocalZ = z
        trackingResult%FinalLocation%TrackingTime = t
        return
      end if

      ! Sanity counters
      dtLoopCounter     = 0
      intLoopCounter    = 0
      posRestartCounter = 0


      ! Local cell time loop 
      exitFace = 0
      continueTimeLoop = .true.
      reachedMaximumTime = .false.
      do while( continueTimeLoop )

          ! Time loop counter
          dtLoopCounter = dtLoopCounter + 1

          ! Update current time
          t = t + dt

          ! Recompute dt for maximumTime 
          if (maximumTime .lt. t) then
              t  = t - dt
              dt = max( maximumTime - t, 0d0 ) ! avoids numerical error effects
              t  = maximumTime
              reachedMaximumTime = .true.
          end if

          ! Compute RWPT movement
          call this%ComputeRWPTDisplacements(       &
                               x, y, z, vx, vy, vz, &
                               dt, trackingOptions, &
                               dAdvx, dAdvy, dAdvz, &
                                     dBx, dBy, dBz, &
                               divDx, divDy, divDz  )

          ! Improve elegance
          ! Vectorize coordinates maybe ?
          dxrw = dAdvx + divDx*dt + dBx*sqrt( dt )
          nx   = x + dxrw/dx
          dyrw = dAdvy + divDy*dt + dBy*sqrt( dt )
          ny   = y + dyrw/dy
          dzrw = dAdvz + divDz*dt + dBz*sqrt( dt )
          nz   = z + dzrw/dz

          ! particleLeavingCell:
          ! Detect if particle leaving the cell
          ! and force the particle into exactly one
          ! interface by computing the required dt
          intLoopCounter = 0
          do while (                                       &
              ( nx .gt. 1.0d0 ) .or. ( nx .lt. 0d0 )  .or. &
              ( ny .gt. 1.0d0 ) .or. ( ny .lt. 0d0 )  .or. &
              ( nz .gt. 1.0d0 ) .or. ( nz .lt. 0d0 )       & 
          )

              intLoopCounter = intLoopCounter + 1
              dtxyz(:) = 0d0

              ! Recompute dt for exact interface
              call this%ExitFaceAndUpdateTimeStep( x, y, z, nx, ny, nz, &
                                       vx, vy, vz, divDx, divDy, divDz, &
                                       dBx, dBy, dBz, t, dt, dtxyz, exitFace )

              if ( intLoopCounter .gt. 3 ) then
                  ! Restart new coordinates 
                  nx = initialLocation%LocalX
                  ny = initialLocation%LocalY
                  nz = initialLocation%LocalZ

                  ! Restart time 
                  t  = t - dt
                  dt = dtold

                  posRestartCounter = posRestartCounter + 1

                  if ( posRestartCounter .gt. 5 ) then 
                    ! Something wrong, leave
                    trackingResult%ExitFace = 0
                    trackingResult%Status = trackingResult%Status_Undefined()
                    trackingResult%FinalLocation%CellNumber = cellNumber
                    trackingResult%FinalLocation%LocalX = x
                    trackingResult%FinalLocation%LocalY = y
                    trackingResult%FinalLocation%LocalZ = z
                    trackingResult%FinalLocation%TrackingTime = t
                    return
                  end if

              end if

              ! Given new dt, recompute advection displacements
              call this%AdvectionDisplacement( x, y, z, dt, vx, vy, vz, & 
                                                    dAdvx, dAdvy, dAdvz )

              ! If maximumTime was reached, but particle left
              ! the cell, then the condition is resetted
              if (reachedMaximumTime) then
                  reachedMaximumTime = .false.
              end if

              ! Find new RWPT displacements
              select case (exitFace)
                ! X Face
                case(1,2)
                  nx   = 1.0d0
                  if ( exitFace .eq. 1 ) nx=0d0
                  dyrw = dAdvy + divDy*dt + dBy*sqrt( dt )
                  ny   = y + dyrw/dy
                  dzrw = dAdvz + divDz*dt + dBz*sqrt( dt )
                  nz   = z + dzrw/dz
                ! Y Face
                case(3,4)
                  dxrw = dAdvx + divDx*dt + dBx*sqrt( dt )
                  nx   = x + dxrw/dx
                  ny   = 1.0d0
                  if ( exitFace .eq. 3 ) ny=0d0
                  dzrw = dAdvz + divDz*dt + dBz*sqrt( dt )
                  nz   = z + dzrw/dz
                ! Z Face
                case(5,6)
                  dxrw = dAdvx + divDx*dt + dBx*sqrt( dt )
                  nx   = x + dxrw/dx
                  dyrw = dAdvy + divDy*dt + dBy*sqrt( dt )
                  ny   = y + dyrw/dy
                  nz   = 1.0d0
                  if ( exitFace .eq. 5 ) nz=0d0
                ! No exit
                case(0)
                  ! Fallback
                  ! If exitFace .eq. 0
                  ! Restart new coordinates 
                  nx = initialLocation%LocalX
                  ny = initialLocation%LocalY
                  nz = initialLocation%LocalZ
                  ! Restart time 
                  t  = t - dt
                  dt = dtold
                  posRestartCounter = posRestartCounter + 1
                  if ( posRestartCounter .gt. 5 ) then 
                    ! Something wrong, leave
                    trackingResult%ExitFace = 0
                    trackingResult%Status = trackingResult%Status_Undefined()
                    trackingResult%FinalLocation%CellNumber = cellNumber
                    trackingResult%FinalLocation%LocalX = x
                    trackingResult%FinalLocation%LocalY = y
                    trackingResult%FinalLocation%LocalZ = z
                    trackingResult%FinalLocation%TrackingTime = t
                    return
                  end if

                  ! Exit interface loop and try again,
                  ! new random displacements
                  exit
              end select

              ! Think how to integrate these conditions into single 
              ! interface loop.  

              ! Found proper interface ?
              !
              ! It is possible that nx,ny,nz are not consistent
              ! values after previous displacement "to the interface".
              ! This effect is originated due to changing direction of displacement vector 
              ! for different dts. So even after finding time step for exitFace,
              ! this new timestep may lead to landing outside the cell from an orthogonal 
              ! direction, typical case of cell corners. If that is the case, then 
              ! interface loop continues but now finding a smaller timestep for the "new" crossing.
              ! 
              if (                                               &
                    ( nx .gt. 1.0d0 ) .or. ( nx .lt. 0d0 )  .or. &
                    ( ny .gt. 1.0d0 ) .or. ( ny .lt. 0d0 )  .or. &
                    ( nz .gt. 1.0d0 ) .or. ( nz .lt. 0d0 )       & 
                ) then 
                  ! Continue looking exact interface
                  continue
              else
                  ! Once the interface is consistent, 
                  ! apply boundary conditions

                  ! Boundary conditions
                  ! Logic should be: 
                  ! Is there an interface and which kind
                  ! At this point, program already 
                  ! found an exitFace
                  ! By default, if a cell is not active from 
                  ! the flow model data, 

                  ! Consider a flag indicating whether the
                  ! center is connected to ANY rebound boundary 

                  ! elasticRebound:
                  ! Verify if particle has to rebound 
                  ! against boundary face.
                  ! Note: one of the possible outputs
                  ! from a reboundBoundary relies on 
                  ! the interface processing 
                  ! being inside the interface detection loop
                  reboundCounter = 0
                  do while( ( exitFace .gt. 0 ) )

                      ! If not connected to rebound boundary cell, leave
                      if ( this%SubCellData%MassBoundary(exitFace) .ne. 1 ) then 
                          exit
                      end if 

                      ! reboundCounter and a catch for unexpected cases
                      reboundCounter = reboundCounter + 1
                      if ( reboundCounter .gt. 10 ) then
                          ! If particle has been rebounding for a long time, stop
                          trackingResult%ExitFace = 0
                          trackingResult%Status   = trackingResult%Status_Undefined()
                          trackingResult%FinalLocation%CellNumber = cellNumber
                          trackingResult%FinalLocation%LocalX = x
                          trackingResult%FinalLocation%LocalY = y
                          trackingResult%FinalLocation%LocalZ = z
                          trackingResult%FinalLocation%TrackingTime = t
                          return
                      end if 


                      ! Save interface positions 
                      xi = nx
                      yi = ny
                      zi = nz
                     

                      ! If dt .eq. 0d0 then the particle is exactly 
                      ! at the interface, and is a rebound interface.
                      ! Stays there ? Becomes inactive ?
                      ! In the meantime, restart.
                      ! This may generate problems for pure advection sims.
                      if ( dt .eq. 0d0 ) then

                          ! Restart new coordinates 
                          nx = initialLocation%LocalX
                          ny = initialLocation%LocalY
                          nz = initialLocation%LocalZ

                          ! Restart time 
                          t  = t - dt
                          dt = dtold
                          exitFace = 0
                          posRestartCounter = posRestartCounter + 1

                          ! With nx, ny, nz adopting the starting values, 
                          ! interface loop is also broken

                          ! Exit rebound loop 
                          exit

                      end if
                      

                      ! Update current time with same time step 
                      ! determined for interface displacement 
                      t = t + dt

                      ! Remember that dt to interface is smaller
                      ! than cell base time step

                      ! In case the new time for an elastic rebound 
                      ! is higher than maximum time, updates dt
                      if (maximumTime .lt. t) then
                          ! Note: if maximumTime is reached in second half of 
                          ! rebound, rebound is shortened

                          ! Recompute time step 
                          t  = t - dt
                          dt = max( maximumTime - t, 0d0 ) ! avoids numerical error effects
                          t  = maximumTime
                          reachedMaximumTime = .true.

                          ! Recompute advection displacement for new time step, 
                          ! as if starting from original position
                          call this%AdvectionDisplacement( x, y, z, dt, vx, vy, vz, dAdvx, dAdvy, dAdvz )

                          ! Recompute RWPT displacements for new dt
                          dxrw = dAdvx + divDx*dt + dBx*sqrt( dt )
                          dyrw = dAdvy + divDy*dt + dBy*sqrt( dt )
                          dzrw = dAdvz + divDz*dt + dBz*sqrt( dt )

                          ! If particle lands outside cell, 
                          ! entering interface loop will modify
                          ! reachedMaximumTime back to .false.
                          !exitFace = 0 ! It is used later so dont' reset yet

                      end if ! maximumTime 

                      ! Particle rebounds with elastic reflection
                      select case ( exitFace )
                        ! X Face
                        case(1,2)
                          nx = nx - dxrw/dx
                          ny = ny + dyrw/dy
                          nz = nz + dzrw/dz
                        ! Y Face
                        case(3,4)
                          nx = nx + dxrw/dx
                          ny = ny - dyrw/dy
                          nz = nz + dzrw/dz
                        ! Z Face
                        case(5,6)
                          nx = nx + dxrw/dx
                          ny = ny + dyrw/dy
                          nz = nz - dzrw/dz
                       end select

                      ! If nx, ny or nz are outside cell interfaces, 
                      ! then the interface loop will continue.
                      ! Set initial particle position to rebound interface
                      if (                                             &
                          ( nx .gt. 1.0d0 ) .or. ( nx .lt. 0d0 )  .or. &
                          ( ny .gt. 1.0d0 ) .or. ( ny .lt. 0d0 )  .or. &
                          ( nz .gt. 1.0d0 ) .or. ( nz .lt. 0d0 )       & 
                      ) then

                          ! Set starting position to rebound interface
                          x = xi
                          y = yi
                          z = zi

                          ! As particle is at the rebound interface, reverts
                          ! displacements of the rebound direction. 
                          ! These are going to be used in determining 
                          ! time step and exact exit position at interface loop
                          if ( ( exitFace .eq. 1 ) .or. ( exitFace .eq. 2 ) ) then 
                            vx    = -vx
                            divDx = -divDx
                            dBx   = -dBx
                          end if 
                          if ( ( exitFace .eq. 3 ) .or. ( exitFace .eq. 4 ) ) then 
                            vy    = -vy
                            divDy = -divDy
                            dBy   = -dBy
                          end if
                          if ( ( exitFace .eq. 5 ) .or. ( exitFace .eq. 6 ) ) then 
                            vz    = -vz
                            divDz = -divDz
                             dBz   = -dBz
                          end if 

                          ! Go to: particleLeavingCell
                          exitFace = 0

                      else
                          ! If nx, ny and nz are inside the cell, then no problem
                          ! particleLeavingCell loop is broken and will update 
                          ! particle position to rebound position and continue
                          ! time loop with cell characteristic time step
                          dt =  dtold
                          exitFace = 0

                          ! If one of the positions is exactly an interface
                          ! Not the most beautiful way
                          if (                                          & 
                              ( nx .eq. 0d0 ) .or. ( nx .eq. 1d0 ) .or. & 
                              ( ny .eq. 0d0 ) .or. ( ny .eq. 1d0 ) .or. & 
                              ( nz .eq. 0d0 ) .or. ( nz .eq. 1d0 )      & 
                          ) then
                              if ( nx .eq. 0d0 ) exitFace = 1 
                              if ( nx .eq. 1d0 ) exitFace = 2
                              if ( ny .eq. 0d0 ) exitFace = 3
                              if ( ny .eq. 1d0 ) exitFace = 4
                              if ( nz .eq. 0d0 ) exitFace = 5
                              if ( nz .eq. 1d0 ) exitFace = 6
                          end if

                      end if ! outsideInterfaces  

                  end do ! elasticRebound

              end if ! If found proper interface

          end do ! particleLeavingCell


          ! Report and leave

          ! Time is up
          if (reachedMaximumTime) then
            ! In this case it is allowed for a particle
            ! to reach the maximum time and eventually have an exit face
            trackingResult%Status = trackingResult%Status_ReachedMaximumTime()
            trackingResult%ExitFace = exitFace
            trackingResult%FinalLocation%CellNumber = cellNumber
            trackingResult%FinalLocation%LocalX = nx
            trackingResult%FinalLocation%LocalY = ny
            trackingResult%FinalLocation%LocalZ = nz
            trackingResult%FinalLocation%TrackingTime = t
            continueTimeLoop = .false.

            ! Done
            return
          end if

          ! Particle left cell
          if( exitFace .gt. 0 ) then 
            ! Based on connected cell id, it is determined 
            ! what happens to the particle (see: source/ModpathCellData.f90:FillSubCellDataBuffer ) 
            ! if ExitFaceConnection = 0, domainBoundary
            ! if ExitFaceConnection > 0, anotherCell
            ! if ExitFaceConnection < 0, subCell, usg-grid
            trackingResult%ExitFaceConnection = this%SubCellData%Connection(exitFace)
            if( trackingResult%ExitFaceConnection .lt. 0 ) then
                ! Internal transfer. This is the case for unstructured grid
                trackingResult%Status = trackingResult%Status_ExitAtInternalFace()
            else
                ! Transfer to another cell
                trackingResult%Status = trackingResult%Status_ExitAtCellFace()
            end if
            trackingResult%ExitFace                   = exitFace
            trackingResult%FinalLocation%CellNumber   = cellNumber
            trackingResult%FinalLocation%LocalX       = nx
            trackingResult%FinalLocation%LocalY       = ny
            trackingResult%FinalLocation%LocalZ       = nz
            trackingResult%FinalLocation%TrackingTime = t
            continueTimeLoop = .false.

            ! Done
            return
          end if 


          ! Update particle positions
          x = nx
          y = ny
          z = nz

      end do ! continueTimeLoop 

      ! Done
      return

  end subroutine pr_ExecuteRandomWalkParticleTracking


  ! RWPT
  subroutine pr_ComputeRandomWalkTimeStep( this, trackingOptions, dt )
      !----------------------------------------------------------------
      ! From user defined options and cell properties, 
      ! compute time step  
      ! 
      ! Params:
      !     - trackingOptions : simulation options
      !     - dt              : time step, output
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class (TrackSubCellType) :: this
      ! input
      type(ParticleTrackingOptionsType),intent(in) :: trackingOptions
      ! output
      doubleprecision, intent(inout) :: dt
      ! local
      doubleprecision :: vx1, vx2, vy1, vy2, vz1, vz2 
      doubleprecision :: dx, dy, dz
      doubleprecision :: alphaL, alphaT
      doubleprecision, dimension(2) :: dts
      !----------------------------------------------------------------

      ! Initialize
      dts(:) = 0d0

      ! Make local copies of face velocities for convenience
      vx1 = this%SubCellData%VX1
      vx2 = this%SubCellData%VX2
      vy1 = this%SubCellData%VY1
      vy2 = this%SubCellData%VY2
      vz1 = this%SubCellData%VZ1
      vz2 = this%SubCellData%VZ2
   
      ! Local copies of cell size
      dx = this%SubCellData%DX
      dy = this%SubCellData%DY
      dz = this%SubCellData%DZ

      ! Local copies of dispersivities 
      alphaL = this%SubCellData%alphaL
      alphaT = this%SubCellData%alphaT

      ! Compute time step
      select case (trackingOptions%timeStepKind)
        case (1)
          ! Advection criteria
          dt = trackingOptions%timeStepParameters(1)/( &
              max(abs(vx1), abs(vx2))/dx +             &
              max(abs(vy1), abs(vy2))/dy +             &
              max(abs(vz1), abs(vz2))/dz )
        case (2)
          ! Dispersion criteria
          ! dt = c_T dx**2/D
          dt = trackingOptions%timeStepParameters(2)/(        &
                   alphaL*max(abs(vx1), abs(vx2))/( dx**2 ) + & 
                   alphaT*max(abs(vy1), abs(vy2))/( dy**2 ) + &
                   alphaT*max(abs(vz1), abs(vz2))/( dz**2 ) )
        case (3)
          ! Advection condition
          ! dt = CFL dx / v 
          dts(1) = trackingOptions%timeStepParameters(1)/( & 
              max(abs(vx1), abs(vx2))/dx +                 &
              max(abs(vy1), abs(vy2))/dy +                 &
              max(abs(vz1), abs(vz2))/dz )
          ! Dispersion condition
          ! dt = c_T dx**2/D
          dts(2) = trackingOptions%timeStepParameters(2)/(    &
                   alphaL*max(abs(vx1), abs(vx2))/( dx**2 ) + & 
                   alphaT*max(abs(vy1), abs(vy2))/( dy**2 ) + &
                   alphaT*max(abs(vz1), abs(vz2))/( dz**2 ) )
          ! Compute minimum
          dt     = minval( dts, dts > 0 )
        case (4)
          ! Fixed
          dt = trackingOptions%timeStepParameters(1)
      end select


  end subroutine pr_ComputeRandomWalkTimeStep


  ! RWPT
  subroutine pr_LinearInterpolationVelocities( this, x, y, z, vx, vy, vz )
      !----------------------------------------------------------------
      ! Computes velocity at given location using cell face velocities
      ! 
      ! Params:
      !     - x, y, z    : local cell coordinates
      !     - vx, vy, vz : holders for velocities, output 
      !                                       
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this
      ! input
      doubleprecision, intent(in) :: x, y, z
      ! output
      doubleprecision, intent(out) :: vx, vy, vz
      !----------------------------------------------------------------

      vx = ( 1.0d0 - x )*this%SubCellData%vx1 + x*this%SubCellData%vx2
      vy = ( 1.0d0 - y )*this%SubCellData%vy1 + y*this%SubCellData%vy2
      vz = ( 1.0d0 - z )*this%SubCellData%vz1 + z*this%SubCellData%vz2

      ! Imagine dimmask is received
      ! or dimensions. 
      ! vvec ! velocities
      ! cvec ! coordinates
      ! do nd = 1, nDim
      !   did = dimensions(nd)
      !   select case( did )
      !    case (1)
      !     vvec(did) = (1.0d0 - cvec(1) )*this%SubCellData%vx1 + cvec(1)*this%SubCellData%vx2
      !    case (2)
      !     vvec(did) = (1.0d0 - cvec(2) )*this%SubCellData%vy1 + cvec(2)*this%SubCellData%vy2
      !    case (3)
      !     vvec(did) = (1.0d0 - cvec(3) )*this%SubCellData%vz1 + cvec(3)*this%SubCellData%vz2
      !   end select
      ! end if

  end subroutine pr_LinearInterpolationVelocities


  ! RWPT
  subroutine pr_AdvectionDisplacementExponential( this, x, y, z, dt, vx, vy, vz, dAdvx, dAdvy, dAdvz )
      !----------------------------------------------------------------
      ! Compute advection displacement using exponential analytical
      ! expression
      ! 
      ! Params: 
      !     - x, y, z             : local cell coordinates
      !     - dt                  : time step
      !     - vx, vy, vz          : interpolated velocities 
      !     - dAdvx, dAdvy, dAdvz : holders for displacements
      !
      ! Interface:
      !     - Advection
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this
      ! input
      doubleprecision, intent(in) :: x, y, z, dt
      doubleprecision, intent(in) :: vx, vy, vz
      ! output
      doubleprecision, intent(inout) :: dAdvx, dAdvy, dAdvz
      ! local
      doubleprecision :: dvxdx, dvydy, dvzdz
      doubleprecision :: dvtol = 1.0d-10
      !----------------------------------------------------------------

      ! Compute displacement
      ! x
      dvxdx = ( this%SubCellData%vx2 - this%SubCellData%vx1 )/this%SubCellData%dx
      if ( ( abs(dvxdx) .gt. dvtol ) ) then
          dAdvx = vx*( exp(dvxdx*dt) - 1.0d0 )/dvxdx
      else
          dAdvx = vx*dt
      end if
      ! y
      dvydy = ( this%SubCellData%vy2 - this%SubCellData%vy1 )/this%SubCellData%dy
      if ( ( abs(dvydy) .gt. dvtol ) ) then
          dAdvy = vy*( exp(dvydy*dt) - 1.0d0 )/dvydy
      else
          dAdvy = vy*dt
      end if
      ! z
      dvzdz = ( this%SubCellData%vz2 - this%SubCellData%vz1 )/this%SubCellData%dz
      if ( ( abs(dvzdz) .gt. dvtol ) ) then
          dAdvz = vz*( exp(dvzdz*dt) - 1.0d0 )/dvzdz
      else
          dAdvz = vz*dt
      end if

  end subroutine pr_AdvectionDisplacementExponential


  ! RWPT
  subroutine pr_AdvectionDisplacementEulerian( this, x, y, z, dt, vx, vy, vz, dAdvx, dAdvy, dAdvz )
      !----------------------------------------------------------------
      ! Compute advection displacement using eulerian approximation 
      ! 
      ! Params: 
      !     - x, y, z             : local cell coordinates
      !     - dt                  : time step
      !     - vx, vy, vz          : interpolated velocities 
      !     - dAdvx, dAdvy, dAdvz : holders for displacements
      !
      ! Interface:
      !     - Advection
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this
      ! input
      doubleprecision, intent(in) :: x, y, z, dt
      doubleprecision, intent(in) :: vx, vy, vz
      ! output
      doubleprecision, intent(inout) :: dAdvx, dAdvy, dAdvz
      !----------------------------------------------------------------
      
      ! Compute displacement
      ! x
      dAdvx = vx*dt
      ! y
      dAdvy = vy*dt
      ! z
      dAdvz = vz*dt

      ! Prototype
      !dAdv = vVec*dt

  end subroutine pr_AdvectionDisplacementEulerian



  ! RWPT
  subroutine pr_DetectExitFaceAndUpdateTimeStepQuadratic( this, x, y, z, nx, ny, nz, & 
               vx, vy, vz, divDx, divDy, divDz, dBx, dBy, dBz, t, dt, dtxyz, exitFace )
      !----------------------------------------------------------------
      ! Detects exit face and computes time step to force particle
      ! into the interface, using analytical quadratic solution method.
      ! Related to eulerian advection model
      ! 
      ! Params:
      !     - x, y, z             : local cell coordinates
      !     - nx, ny, nz          : updated coordinates after RWPT
      !     - vx, vy, vz          : interpolated velocities
      !     - divDx, divDy, divDz : dispersion divergence
      !     - dBx, dBy, dBz       : random dispersion displacements
      !     - t                   : current time
      !     - dt                  : time step
      !     - dtxyz               : array for saving each dt
      !     - exitFace            : holder for exit face
      !  
      ! Interface:
      !     - ExitFaceAndTimeStep
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class (TrackSubCellType) :: this
      ! input
      doubleprecision, intent(in) :: x, y, z
      doubleprecision, intent(in) :: nx, ny, nz
      doubleprecision, intent(in) :: vx, vy, vz
      doubleprecision, intent(in) :: divDx, divDy, divDz
      doubleprecision, intent(in) :: dBx, dBy, dBz
      ! output
      doubleprecision, intent(inout) :: t, dt
      integer, intent(inout)         :: exitFace
      doubleprecision, dimension(3), intent(inout) :: dtxyz
      ! local
      integer :: exitFaceX, exitFaceY, exitFaceZ
      integer :: imindt
      doubleprecision :: dx, dy, dz
      doubleprecision :: dInterface
      doubleprecision :: AFace, BFace, z1, z2, zsqrt, zsqrtarg
      !----------------------------------------------------------------
        

      ! Initialize
      exitFaceX  = 0
      exitFaceY  = 0
      exitFaceZ  = 0

      ! Local copies of cell size 
      dx = this%SubCellData%DX
      dy = this%SubCellData%DY
      dz = this%SubCellData%DZ

      !Reset t, dt will be replaced
      t = t - dt

      ! Leaving through x face
      dInterface = 0d0
      AFace      = 0d0
      BFace      = 0d0
      z1         = 0d0
      z2         = 0d0
      zsqrt      = 0d0 
      zsqrtarg   = 0d0 
      if ( ( nx .gt. 1.0d0 ) .or. ( nx .lt. 0d0 )  ) then

          ! Compute dInterface
          if ( nx .gt. 1.0d0 ) then 
              dInterface = dx*( 1.0d0 - x )
              exitFaceX  = 2
          else 
              dInterface = -dx*x
              exitFaceX  = 1
          end if

          ! Exactly at interface, force new cell
          if ( dInterface .eq. 0d0 ) then
              exitFace = exitFaceX
              dt = 0.0 
              return
          end if

          ! Coefficients
          AFace = vx + divDx
          BFace = dBx

          ! Given dInterface, compute new dt
          zsqrtarg = BFace**2 + 4*dInterface*AFace

          if ( ( zsqrtarg .ge. 0d0 ) .and. ( AFace .ne. 0d0 ) ) then 
              zsqrt = sqrt( zsqrtarg )
              z1    = (-BFace + zsqrt )/( 2*AFace )
              z2    = (-BFace - zsqrt )/( 2*AFace )

              if ( any( (/ z1, z2 /) .gt. 0d0) ) then 
                  ! Compute new dt
                  dtxyz(1) = minval( (/z1, z2/), mask=(/z1, z2/)>0d0 )**2
                  ! If computed dt is zero, then 
                  ! particle is at the interface
                  if ( dtxyz(1) .eq. 0d0 ) then
                      exitFace = exitFaceX
                      dt = 0.0 
                      return
                  end if
              else if ( any( (/ z1, z2 /) .eq. 0d0) ) then 
                  ! This is equivalent to being at the interface, 
                  ! It didn't detected any solution gt 0, but one zero,
                  ! which means interface
                  exitFace = exitFaceX
                  dt       = 0.0
                  return
              end if

          else if ( AFace .eq. 0d0 ) then 
              ! If A is zero, then the equation is linear
              ! At this point, it is important to note
              ! that dInterface is non zero, but could be really small
              if ( BFace .ne. 0d0 ) then 
                  dtxyz(1) = ( dInterface/BFace )**2
                  ! If computed dt is zero, then 
                  ! particle is at the interface
                  if ( dtxyz(1) .eq. 0d0 ) then
                      exitFace = exitFaceX
                      dt = 0.0 
                      return
                  end if
              end if 
          end if

          ! If computed dt is higher than current
          ! is not valid, set to zero
          if ( dtxyz(1) .gt. dt ) dtxyz(1) = 0d0

      end if

      ! Leaving through y face
      dInterface = 0d0
      AFace      = 0d0
      BFace      = 0d0
      z1         = 0d0
      z2         = 0d0
      zsqrt      = 0d0 
      zsqrtarg   = 0d0 
      if ( ( ny .gt. 1.0d0 ) .or. ( ny .lt. 0d0 )  ) then

          ! Compute dInterface
          if ( ny .gt. 1.0d0 ) then 
              dInterface = dy*( 1.0d0 - y )
              exitFaceY  = 4
          else 
              dInterface = -dy*y
              exitFaceY  = 3
          end if

          ! Exactly at interface, force new cell
          if ( dInterface .eq. 0.0 ) then
              exitFace = exitFaceY
              dt = 0.0
              return
          end if

          ! Coefficients
          AFace = vy + divDy
          BFace = dBy

          ! Given dInterface, compute new dt
          zsqrtarg = BFace**2 + 4*dInterface*AFace

          if ( ( zsqrtarg .ge. 0d0 ) .and. ( AFace .ne. 0d0 ) ) then
              zsqrt = sqrt( zsqrtarg )
              z1    = (-BFace + zsqrt )/( 2*AFace )
              z2    = (-BFace - zsqrt )/( 2*AFace )

              if ( any( (/ z1, z2 /) .gt. 0d0) ) then 
                  ! Compute new dt
                  dtxyz(2) = minval( (/z1, z2/), mask=(/z1, z2/)>0d0 )**2
                  ! If computed dt is zero, then 
                  ! particle is at the interface
                  if ( dtxyz(2) .eq. 0d0 ) then
                      exitFace = exitFaceY
                      dt = 0.0 
                      return
                  end if
              else if ( any( (/ z1, z2 /) .eq. 0d0) ) then 
                  ! This is equivalent to being at the interface, 
                  ! It didn't detected any solution gt 0, but one zero,
                  ! which means interface
                  exitFace = exitFaceY
                  dt       = 0.0
                  return
              end if

          else if ( AFace .eq. 0d0 ) then 
              ! If A is zero, then the equation is linear
              ! At this point, it is important to note
              ! that dInterface is non zero, but could be really small
              if ( BFace .ne. 0d0 ) then 
                  dtxyz(2) = ( dInterface/BFace )**2
                  ! If computed dt is zero, then 
                  ! particle is at the interface
                  if ( dtxyz(2) .eq. 0d0 ) then
                      exitFace = exitFaceY
                      dt = 0.0 
                      return
                  end if
              end if 
          end if

          ! If computed dt is higher than current
          ! is not valid, set to zero
          if ( dtxyz(2) .gt. dt ) dtxyz(2) = 0d0

      end if

      ! Leaving through z face
      dInterface = 0d0
      AFace      = 0d0
      BFace      = 0d0
      z1         = 0d0
      z2         = 0d0
      zsqrt      = 0d0 
      zsqrtarg   = 0d0 
      if ( ( nz .gt. 1.0d0 ) .or. ( nz .lt. 0d0 )  ) then

          ! Compute dInterface
          if ( nz .gt. 1.0d0 ) then
              dInterface = dz*( 1.0d0 - z )
              exitFaceZ  = 6
          else
              dInterface = -dz*z
              exitFaceZ  = 5
          end if

          ! Exactly at interface, force new cell
          if ( dInterface .eq. 0.0 ) then
              exitFace = exitFaceZ
              dt = 0.0
              return
          end if

          ! Coefficients
          AFace = vz + divDz
          BFace = dBz
        
          ! Given dInterface, compute new dt
          zsqrtarg = BFace**2 + 4*dInterface*AFace

          if ( ( zsqrtarg .ge. 0d0 ) .and. ( AFace .ne. 0d0 ) )  then
              zsqrt = sqrt( zsqrtarg )
              z1    = (-BFace + zsqrt )/( 2*AFace )
              z2    = (-BFace - zsqrt )/( 2*AFace )

              if ( any( (/ z1, z2 /) .gt. 0d0 ) ) then 
                  ! Compute new dt
                  dtxyz(3) = minval( (/z1, z2/), mask=(/z1, z2/)>0d0 )**2
                  ! If computed dt is zero, then 
                  ! particle is at the interface
                  if ( dtxyz(3) .eq. 0d0 ) then
                      exitFace = exitFaceZ
                      dt = 0.0 
                      return
                  end if
              else if ( any( (/ z1, z2 /) .eq. 0d0) ) then 
                  ! This is equivalent to being at the interface, 
                  ! It didn't detected any solution gt 0, but one zero,
                  ! which means interface
                  exitFace = exitFaceZ
                  dt       = 0.0
                  return
              end if

          else if ( AFace .eq. 0d0 ) then 
              ! If A is zero, then the equation is linear
              ! At this point, it is important to note
              ! that dInterface is non zero
              if ( BFace .ne. 0d0 ) then 
                  dtxyz(3) = ( dInterface/BFace )**2
                  ! If computed dt is zero, then 
                  ! particle is at the interface
                  if ( dtxyz(3) .eq. 0d0 ) then
                      exitFace = exitFaceZ
                      dt = 0.0 
                      return
                  end if
              end if 
          end if

          ! If computed dt is higher than current
          ! is not valid, set to zero
          if ( dtxyz(3) .gt. dt ) dtxyz(3) = 0d0 

      end if


      ! If all dts where zero, restore t + dt
      ! and leave
      if ( all( dtxyz .eq. 0d0 ) ) then 
          t = t + dt
          return
      end if


      ! Find minimum dt and 
      ! assign values accordingly
      imindt = minloc( dtxyz, dim=1, mask=(dtxyz > 0d0) )
      dt     = dtxyz(imindt)

      if ( imindt .eq. 1 ) then
          exitFace = exitFaceX
      else if ( imindt .eq. 2 ) then
          exitFace = exitFaceY
      else if ( imindt .eq. 3 ) then
          exitFace = exitFaceZ
      end if


      ! Update time
      t = t + dt


  end subroutine pr_DetectExitFaceAndUpdateTimeStepQuadratic


  subroutine pr_DetectExitFaceAndUpdateTimeStepNewton( this, x, y, z, nx, ny, nz, & 
            vx, vy, vz, divDx, divDy, divDz, dBx, dBy, dBz, t, dt, dtxyz, exitFace )
      !----------------------------------------------------------------
      ! Detects exit face and computes time step to force particle
      ! into the interface, using newton raphson method. 
      ! Related to exponential advection model 
      ! 
      ! Params:
      !     - x, y, z             : local cell coordinates
      !     - nx, ny, nz          : updated coordinates after RWPT
      !     - vx, vy, vz          : interpolated velocities
      !     - divDx, divDy, divDz : dispersion divergence
      !     - dBx, dBy, dBz       : random dispersion displacements
      !     - t                   : current time
      !     - dt                  : time step
      !     - dtxyz               : array for saving each dt
      !     - exitFace            : holder for exit face
      !  
      ! Interface:
      !     - ExitFaceAndTimeStep
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class (TrackSubCellType) :: this
      ! input
      doubleprecision, intent(in) :: x, y, z
      doubleprecision, intent(in) :: nx, ny, nz
      doubleprecision, intent(in) :: vx, vy, vz
      doubleprecision, intent(in) :: divDx, divDy, divDz
      doubleprecision, intent(in) :: dBx, dBy, dBz
      ! output
      doubleprecision, intent(inout) :: t, dt
      integer, intent(inout)         :: exitFace
      doubleprecision, dimension(3), intent(inout) :: dtxyz
      ! local
      integer :: exitFaceX, exitFaceY, exitFaceZ
      integer :: imindt
      doubleprecision :: dx, dy, dz
      doubleprecision :: dInterface
      !----------------------------------------------------------------

      ! Initialize
      exitFaceX  = 0
      exitFaceY  = 0
      exitFaceZ  = 0

      ! Local copies of cell size 
      dx = this%SubCellData%DX
      dy = this%SubCellData%DY
      dz = this%SubCellData%DZ

      !Reset t, dt will be replaced
      t = t - dt

      ! Leaving through x face
      dInterface = 0d0
      if ( ( nx .gt. 1.0d0 ) .or. ( nx .lt. 0d0 )  ) then

          ! Compute dInterface
          if ( nx .gt. 1.0d0 ) then 
              dInterface = dx*( 1.0d0 - x )
              exitFaceX  = 2
          else 
              dInterface = -dx*x
              exitFaceX  = 1
          end if

          ! Exactly at interface, force new cell
          if ( dInterface .eq. 0d0 ) then
              exitFace = exitFaceX
              dt = 0d0
              return
          end if

          ! Solve
          call this%NewtonRaphsonTimeStep( dt, vx,              &
                                           this%SubCellData%vx1,&
                                           this%SubCellData%vx2,&
                                           this%SubCellData%dx, &
                                           dInterface, divDx,   & 
                                           dBx, dtxyz(1) )

          ! If computed dt is higher than current
          ! is not valid, set to zero
          if ( dtxyz(1) .gt. dt ) dtxyz(1) = 0d0

      end if


      ! Leaving through y face
      dInterface = 0d0
      if ( ( ny .gt. 1.0d0 ) .or. ( ny .lt. 0d0 )  ) then

          ! Compute dInterface
          if ( ny .gt. 1.0d0 ) then 
              dInterface = dy*( 1.0d0 - y )
              exitFaceY  = 4
          else 
              dInterface = -dy*y
              exitFaceY  = 3
          end if

          ! Exactly at interface, force new cell
          if ( dInterface .eq. 0d0 ) then
              exitFace = exitFaceY
              dt = 0d0
              return
          end if

          ! Solve
          call this%NewtonRaphsonTimeStep( dt, vy,              &
                                           this%SubCellData%vy1,&
                                           this%SubCellData%vy2,&
                                           this%SubCellData%dy, &
                                           dInterface, divDy,   & 
                                           dBy, dtxyz(2) )

          ! If computed dt is higher than current
          ! is not valid, set to zero
          if ( dtxyz(2) .gt. dt ) dtxyz(2) = 0d0

      end if


      ! Leaving through z face
      dInterface = 0d0
      if ( ( nz .gt. 1.0d0 ) .or. ( nz .lt. 0d0 )  ) then

          ! Compute dInterface
          if ( nz .gt. 1.0d0 ) then
              dInterface = dz*( 1.0d0 - z )
              exitFaceZ  = 6
          else
              dInterface = -dz*z
              exitFaceZ  = 5
          end if

          ! Exactly at interface, force new cell
          if ( dInterface .eq. 0d0 ) then
              exitFace = exitFaceZ
              dt = 0d0
              return
          end if

          ! Solve
          call this%NewtonRaphsonTimeStep( dt, vz,              &
                                           this%SubCellData%vz1,&
                                           this%SubCellData%vz2,&
                                           this%SubCellData%dz, &
                                           dInterface, divDz,   & 
                                           dBz, dtxyz(3) )

          ! If computed dt is higher than current
          ! is not valid, set to zero
          if ( dtxyz(3) .gt. dt ) dtxyz(3) = 0d0

      end if


      ! If all dts where zero, restore t + dt
      ! and leave
      if ( all( dtxyz .eq. 0d0 ) ) then 
          t = t + dt
          return
      end if


      ! Find minimum dt and 
      ! assign values accordingly
      imindt = minloc( dtxyz, dim=1, mask=(dtxyz > 0d0) )
      dt     = dtxyz(imindt)
      if ( imindt .eq. 1 ) then
          exitFace = exitFaceX
      else if ( imindt .eq. 2 ) then
          exitFace = exitFaceY
      else if ( imindt .eq. 3 ) then
          exitFace = exitFaceZ
      end if


      ! Update time
      t = t + dt


  end subroutine pr_DetectExitFaceAndUpdateTimeStepNewton



  subroutine pr_NewtonRaphsonVariablesExponential( this, dt, v, v1, v2, &
                                              dx, dInterface, divD, dB, & 
                                      nrf0, nrfprim, nrf2prim, nrf3prim )
  !-----------------------------------------------------------------------------
  ! Specifications
  !-----------------------------------------------------------------------------
  implicit none
  class(TrackSubCellType) :: this
  doubleprecision, intent(in)    :: dt
  doubleprecision, intent(in)    :: v, v1, v2, dx, dInterface, divD, dB
  doubleprecision, intent(inout) :: nrf0, nrfprim, nrf2prim, nrf3prim
  doubleprecision :: dvdx, dAdv
  doubleprecision :: dvtol = 1.0d-10 ! a parameter declaration at module level ? 
  !-----------------------------------------------------------------------------

    if ( dt.eq.0d0 ) return

    ! Initialize
    nrf0      = 0d0
    nrfprim   = 0d0
    nrf2prim  = 0d0
    nrf3prim  = 0d0
    dvdx      = ( v2 - v1 )/dx

    ! Advection
    if ( abs(dvdx) > dvtol ) then 
      dAdv = v*( exp( dvdx*dt ) - 1.0 )/dvdx
    else
      dAdv = v*dt
    end if

    ! Derivatives and iteration terms
    nrf0     = dAdv + divD*dt + dB*sqrt( dt ) - dInterface
    nrfprim  = v*exp( dvdx*dt ) + divD + 0.5*dB/sqrt( dt )
    nrf2prim = dvdx*v*exp( dvdx*dt ) - 0.25*dB*dt**(-1.5)
    nrf3prim = dvdx*dvdx*v*exp( dvdx*dt ) + 0.375*dB*dt**(-2.5)

    ! Done
    return

  end subroutine pr_NewtonRaphsonVariablesExponential



  function pr_GetConvergenceFunction( this, nrf0, nrfprim, nrf2prim ) result( gprim )
  !----------------------------------------------------------------
  ! Specifications
  !----------------------------------------------------------------
  implicit none
  class(TrackSubCellType) :: this
  doubleprecision, intent(in) :: nrf0, nrfprim, nrf2prim
  doubleprecision :: gprim 
  !----------------------------------------------------------------
  
    gprim    = abs( nrf2prim*nrf0 / nrfprim**2 )

    ! Done
    return

  end function pr_GetConvergenceFunction



  function pr_GetConvergenceFunctionDerivative( this, nrf0, nrfprim, nrf2prim, nrf3prim ) result( gprimder )
  !----------------------------------------------------------------
  !----------------------------------------------------------------
  implicit none
  class(TrackSubCellType) :: this
  doubleprecision, intent(in) :: nrf0, nrfprim, nrf2prim, nrf3prim
  doubleprecision :: gprimnoabs, gprimder, gprimprim
  !----------------------------------------------------------------

    gprimnoabs = nrf2prim*nrf0/nrfprim**2
    gprimprim  = -2d0*( nrf0*nrf2prim**2 )/( nrfprim**3 ) + ( nrfprim*nrf2prim + nrf0*nrf3prim )/( nrfprim**2 )
    gprimder   = gprimnoabs/abs( gprimnoabs )*gprimprim

    ! Done      
    return

  end function pr_GetConvergenceFunctionDerivative



  function pr_SetInitialGuess( this, dt, v, v1, v2, dx, dInterface, divD, dB ) result( dtnew )
  !----------------------------------------------------------------
  ! Specifications
  !----------------------------------------------------------------
  implicit none
  class(TrackSubCellType) :: this
  doubleprecision, intent(in) :: dt
  doubleprecision, intent(in) :: v, v1, v2, dx, dInterface, divD, dB
  doubleprecision :: dtnew, dtold, dt0 
  doubleprecision :: nrf0, nrfprim
  doubleprecision :: nrf2prim, nrf3prim
  doubleprecision :: gprimdernew, gprimnew
  doubleprecision :: gprimder, gprim, gprimmin
  doubleprecision :: gamman
  doubleprecision :: dtfraction, dtoldfraction
  doubleprecision :: mindtfrac
  doubleprecision :: gdtol  = 1e-6
  integer         :: maxter = 50
  integer         :: counter
  integer         :: ccount
  integer         :: bcount
  integer         :: zcount
  integer         :: rcount
  integer         :: gcount
  !----------------------------------------------------------------

    ! Check 
    dtnew = 0d0
    if ( dt.eq.0d0 ) return

    ! Initialize
    gprimmin  = 1e10
    gprim     = 1e10

    ! Estimate order of initial dt fraction
    ! Run over very small fractions
    gcount = 0
    do while ( ( gprim .gt. 1 ) .and. ( gcount .lt. 7 ) )
      gcount     = gcount + 1
      dtfraction = 10d0**( -8 + gcount )
      dt0        = dt*dtfraction
      call pr_NewtonRaphsonVariablesExponential( this, dt0, v, v1, v2, &
                                             dx, dInterface, divD, dB, & 
                                     nrf0, nrfprim, nrf2prim, nrf3prim )
      gprim = pr_GetConvergenceFunction( this, nrf0, nrfprim, nrf2prim )
      if ( gprim .lt. gprimmin ) then 
        gprimmin  = gprim
        mindtfrac = dtfraction
      end if 
    end do


    ! Set smaller fraction for gradient descent 
    if ( ( gprim .lt. 1 ) .and. ( gcount .eq. 1 ) ) then  
      dtoldfraction = 1d-8 
    else if ( gprim .lt. 1 ) then 
      dtoldfraction =  10d0**( -8 + gcount - 1 )
    else
      dtfraction    = mindtfrac
      dtoldfraction = 0.5*dtfraction/10d0      
    end if 
   
    ! Set initial dt, dtold
    dtnew  = dtfraction*dt
    dtold  = dtoldfraction*dt 

    ! Do it or leave ? 
    call pr_NewtonRaphsonVariablesExponential( this, dtnew, v, v1, v2, &
                                           dx, dInterface, divD, dB, & 
                                   nrf0, nrfprim, nrf2prim, nrf3prim )
    gprim = pr_GetConvergenceFunction( this, nrf0, nrfprim, nrf2prim )

    if ( gprim .lt. 0.5 ) then 
        ! Done 
        return
    end if

    
    ! Continue to gradient descent  
    gprimnew = 10d0
    gprim    = 10d0
    ccount  = 0
    bcount  = 0
    zcount  = 0
    rcount  = 0
    counter = 0
    do while ( counter .lt. maxter )

        counter = counter + 1 

        ! Compute quantities for gradient descent
        call pr_NewtonRaphsonVariablesExponential( this, dtold, v, v1, v2, &
                                                 dx, dInterface, divD, dB, & 
                                         nrf0, nrfprim, nrf2prim, nrf3prim )
        gprimder  = pr_GetConvergenceFunctionDerivative( this, nrf0, nrfprim, nrf2prim, nrf3prim )

        call pr_NewtonRaphsonVariablesExponential( this, dtnew, v, v1, v2, &
                                                 dx, dInterface, divD, dB, & 
                                         nrf0, nrfprim, nrf2prim, nrf3prim )
        gprimdernew = pr_GetConvergenceFunctionDerivative( this, nrf0, nrfprim, nrf2prim, nrf3prim )
        gprim       = pr_GetConvergenceFunction( this, nrf0, nrfprim, nrf2prim )

        ! Compute gamma gradient descent and update
        if ( ( gprimdernew - gprimder ) .gt. 0d0 ) then
            gamman = abs( ( dtnew - dtold )*( gprimdernew - gprimder ) )/( ( gprimdernew - gprimder )**2 )
        else 
            gamman = 0d0
        end if 
        dtold = dtnew
        dtnew = dtnew - gamman*gprimdernew

        ! If nan, leave loop
        if ( isnan( dtnew ) ) then 
           dtnew = 0d0 
           exit
        end if 

        ! Bound dtnew to values smaller than one or leave if ready
        if ( ( gprim .lt. 1 ) .and. ( dtnew/dt .gt. 1 ) ) then

            dtnew = dtold

            ! Done
            return
      
        else if ( dtnew/dt .gt. 1 ) then 

            dtnew = 0.99*dt

        end if 

        ! Bound dtnew values higher than zero
        ! If convergence parameter already smaller than one
        ! set to dtold and leave.
        if ( ( gprim .lt. 1 ) .and. ( dtnew .lt. 0 ) .and. ( dtold .gt. 0 )  )  then

            dtnew = dtold

            ! Done
            return

        else if ( dtnew .lt. 0 ) then
            ! If smaller than zero but no convergence 
            ! yet, count how many times this happens 
            ! and leave after twice. Probably a very small value
            ! close to zero  

            dtnew = 1e-8*dt 
            zcount = zcount + 1 

            if ( zcount .gt. 1 ) then 
            
                dtnew = 0d0
                
                ! Leave loop
                exit

            end if 

        end if


        call pr_NewtonRaphsonVariablesExponential( this, dtnew, v, v1, v2, &
                                                 dx, dInterface, divD, dB, & 
                                         nrf0, nrfprim, nrf2prim, nrf3prim )
        gprimnew = pr_GetConvergenceFunction( this, nrf0, nrfprim, nrf2prim )


        ! If values appropiate for convergence,
        ! leave after two consecutive occurrences
        if ( ( gprimnew .lt. 1 ) .and. ( dtnew .gt. 0 ) .and. ( dtnew/dt .lt. 1 ) ) then 

            rcount = rcount + 1
            if ( rcount .gt. 1 ) then 
                ! Done
                return
            end if
        else 
            rcount = 0
        end if 


        ! If convergence function is already
        ! less than one and the method provides
        ! a higher value for the new 
        ! convergence function, leave
        if ( ( gprim .lt. 1 ) .and. ( gprimnew .gt. gprim ) ) then

            dtnew = dtold
            
            ! Done
            return

        end if 


        ! If max iterations, exit do loop
        if ( counter .gt. maxter ) then 
            ! Leave loop  
            exit
        end if 


        ! If changes in initial guess
        ! are small, at least twice consecutive,
        ! then leave
        if ( ( abs( (dtold - dtnew)/dtold ) < gdtol ) .and. ( gprim .lt. 1 )  ) then

            ccount = ccount + 1
            if ( ccount .gt. 1 ) then 
                ! Done 
                return 
            end if 
        else 
            ccount = 0
        end if

        
        ! If relative changes in estimate are small and 
        ! convergence function not good, leave and try 
        ! higher orders
        if ( ( abs( (dtold - dtnew)/dtold ) < gdtol ) .and. ( gprim .gt. 1 )  ) then

            bcount = bcount + 1

            if ( bcount .gt. 1 ) then
                ! Leave loop  
                exit
            end if 
    
        else 
            bcount = 0
        end if


    end do


    ! Needed ?
    if ( gprim .lt. 1 ) then 
        ! Done
        return 
    end if 


    ! Continue and try with higher order fractions
    gprim     = 1e10
    gprimmin  = 1e10
    mindtfrac = 0d0

    ! Run over higher order fractions 
    gcount = 1
    do while ( ( gprim .gt. 1 ) .and. ( gcount .lt. 9 ) )

      gcount     = gcount + 1
      dtfraction = 0.1*gcount
      dt0        = dt*dtfraction

      call pr_NewtonRaphsonVariablesExponential( this, dt0, v, v1, v2, &
                                             dx, dInterface, divD, dB, & 
                                     nrf0, nrfprim, nrf2prim, nrf3prim )
      gprim = pr_GetConvergenceFunction( this, nrf0, nrfprim, nrf2prim )
  
      if ( gprim .lt. gprimmin ) then  
          gprimmin  = gprim
          mindtfrac = dtfraction
      end if 

    end do

    ! If any was smaller than one,
    ! set those values and leave
    if ( gprimmin .lt. 1 ) then 
        dtnew = dt*mindtfrac
    end if 

    ! Set advection condition if zero and v, otherwise zero 
    if ( ( dtnew .le. 0d0 ) .and. ( abs( v ) .gt. 0d0 ) ) then 
        dtnew = abs( dInterface/v )
    end if 


    ! Done
    return
        

  end function pr_SetInitialGuess


  subroutine NewtonRaphsonTimeStepExponentialAdvection( this, dt, v, v1, v2, &
                                              dx, dInterface, divD, dB, dtnr )
      !----------------------------------------------------------------
      ! Computes time step required to reach interface by RWPT
      ! with exponential integration of advection, only one axis
      !
      ! Params:
      !     - dt         : time step that moved a particle outside the cell
      !     - v          : interpolated velocity at particle's position
      !     - v1, v2     : cell faces velocity
      !     - dx         : cell size
      !     - dInterface : distance to axis interface
      !     - divD       : dispersion divergence
      !     - dB         : random dispersion displacement
      !     - dtnr       : time step computed with NR, output
      !
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this
      ! input 
      doubleprecision, intent(in)  :: dt 
      doubleprecision, intent(in)  :: v, v1, v2, dx, dInterface, divD, dB
      ! output
      doubleprecision, intent(out) :: dtnr
      ! local
      doubleprecision :: dvdx, dAdv
      doubleprecision :: dt0
      doubleprecision :: nrf0, nrfprim, nrerror
      doubleprecision :: dvtol = 1.0d-10
      doubleprecision :: nrtol = 1e-6
      integer :: countIter
      integer :: maxIter = 50
      ! Note
      ! Compute 
      !    abs(f*ftwoprim) .lt. abs(fprim**2)
      ! https://math.stackexchange.com/questions/3136446/condition-for-convergence-of-newton-raphson-method
      !----------------------------------------------------------------

      ! Initialize
      nrf0      = 0d0
      nrfprim   = 0d0
      nrerror   = 1d6 ! Something big
      dvdx      = ( v2 - v1 )/dx

      ! Initial time step estimate
      dt0 = pr_SetInitialGuess( this, dt, v, v1, v2, dx, dInterface, divD, dB )

      ! If no proper initial guess, leave
      if ( dt0 .eq. 0d0 ) then 
        dtnr = 0d0 
        return
      end if 

      ! Iteration until convergence or maxIterations
      countIter = 0
      do while( ( abs(nrerror/dt0) .gt. nrtol ) .and. ( countIter .lt. maxIter ) )

        countIter = countIter + 1

        ! Compute displacement, although initially this 
        ! should be known
        if ( ( abs(dvdx) .gt. dvtol ) ) then
          dAdv = v*( exp(dvdx*dt0) - 1.0d0 )/dvdx
        else
          dAdv = v*dt0
        end if

        ! RWPT displacement with initial guess
        nrf0  = dAdv + divD*dt0 + dB*sqrt( dt0 ) - dInterface

        ! Analytical derivative of RWPT displacement
        nrfprim  = v*exp(dvdx*dt0) + divD + 0.5*dB/sqrt(dt0) 

        ! NR error and new time step
        nrerror = -nrf0/nrfprim
        dt0     = dt0 + nrerror 

        ! It can't be smaller than zero
        if ( dt0 .lt. 0d0 ) then
          dt0 = -0.9*dt0   
        end if 

      end do

      ! Assign return value
      dtnr = dt0

      ! If new value higher than the previous, return zero 
      if ( dt0 .gt. dt ) then
        dtnr = dt
        ! Done
        return 
      end if 

      ! If no convergence, return zero
      if ( ( countIter .eq. maxIter ) .and. ( abs(nrerror/dt0) .gt. nrtol ) ) then
        ! Done
        dtnr = 0d0 
        return 
      end if



  end subroutine NewtonRaphsonTimeStepExponentialAdvection


  ! RWPT
  subroutine pr_DispersionDivergenceDischarge( this, x, y, z, alphaL, alphaT, dMEff, divDx, divDy, divDz )
      !----------------------------------------------------------------
      ! Compute dispersion divergence terms 
      ! 
      ! Params:
      !     - x, y, z             : local cell coordinates
      !     - alphaL              : longidutinal dispersivity
      !     - alphaT              : transverse dispersivity
      !     - dMEff               : effective molecular diffusion (corrected by tortuosity)
      !     - divDx, divDy, divDz : dispersion divergence, output 
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class (TrackSubCellType)    :: this
      ! input
      doubleprecision, intent(in) :: x, y, z
      doubleprecision, intent(in) :: alphaL, alphaT, dMEff
      ! output
      doubleprecision, intent(out) :: divDx, divDy, divDz
      ! local
      doubleprecision, dimension(4) :: q000
      doubleprecision, dimension(4) :: q100
      doubleprecision, dimension(4) :: q010
      doubleprecision, dimension(4) :: q110
      doubleprecision, dimension(4) :: q001
      doubleprecision, dimension(4) :: q101
      doubleprecision, dimension(4) :: q011
      doubleprecision, dimension(4) :: q111

      doubleprecision :: dDxxdx, dDxydy, dDxzdz, &
                         dDxydx, dDyydy, dDyzdz, &
                         dDxzdx, dDyzdy, dDzzdz

      doubleprecision :: aLMinusaT

      doubleprecision :: pDmeff000
      doubleprecision :: pDmeff100
      doubleprecision :: pDmeff010
      doubleprecision :: pDmeff110
      doubleprecision :: pDmeff001
      doubleprecision :: pDmeff101
      doubleprecision :: pDmeff011
      doubleprecision :: pDmeff111

      doubleprecision :: Dxxx000, Dyyy000, Dzzz000 
      doubleprecision :: Dxxx100, Dyyy100, Dzzz100
      doubleprecision :: Dxxx010, Dyyy010, Dzzz010
      doubleprecision :: Dxxx110, Dyyy110, Dzzz110
      doubleprecision :: Dxxx001, Dyyy001, Dzzz001
      doubleprecision :: Dxxx101, Dyyy101, Dzzz101
      doubleprecision :: Dxxx011, Dyyy011, Dzzz011
      doubleprecision :: Dxxx111, Dyyy111, Dzzz111

      doubleprecision :: Dxyx000, Dxzx000, Dxyy000 
      doubleprecision :: Dxyx100, Dxzx100, Dxyy100
      doubleprecision :: Dxyx010, Dxzx010, Dxyy010
      doubleprecision :: Dxyx110, Dxzx110, Dxyy110
      doubleprecision :: Dxyx001, Dxzx001, Dxyy001
      doubleprecision :: Dxyx101, Dxzx101, Dxyy101
      doubleprecision :: Dxyx011, Dxzx011, Dxyy011
      doubleprecision :: Dxyx111, Dxzx111, Dxyy111

      doubleprecision :: Dyzy000, Dxzz000, Dyzz000 
      doubleprecision :: Dyzy100, Dxzz100, Dyzz100
      doubleprecision :: Dyzy010, Dxzz010, Dyzz010
      doubleprecision :: Dyzy110, Dxzz110, Dyzz110
      doubleprecision :: Dyzy001, Dxzz001, Dyzz001
      doubleprecision :: Dyzy101, Dxzz101, Dyzz101
      doubleprecision :: Dyzy011, Dxzz011, Dyzz011
      doubleprecision :: Dyzy111, Dxzz111, Dyzz111
      !---------------------------------------------------------------- 

      ! Initialize output !
      divDx = 0d0 
      divDy = 0d0
      divDz = 0d0
        
      ! qx, qy, qz, norm(q)
      q000 = this%qCorner000 
      q100 = this%qCorner100
      q010 = this%qCorner010
      q110 = this%qCorner110
      q001 = this%qCorner001
      q101 = this%qCorner101
      q011 = this%qCorner011
      q111 = this%qCorner111
 
      ! alphaL - alphaT
      aLMinusaT = alphaL - alphaT

      ! Product between porosities and effecfive molecular diffusion 
      pDMeff000 = this%porosity000*dMEff 
      pDMeff100 = this%porosity100*dMEff
      pDMeff010 = this%porosity010*dMEff
      pDMeff110 = this%porosity110*dMEff
      pDMeff001 = this%porosity001*dMEff
      pDMeff101 = this%porosity101*dMEff
      pDMeff011 = this%porosity011*dMEff
      pDMeff111 = this%porosity111*dMEff

      ! Initialize !
      ! dDxxdx
      Dxxx000 = pDMeff000
      Dxxx100 = pDMeff100
      Dxxx010 = pDMeff010
      Dxxx110 = pDMeff110
      Dxxx001 = pDMeff001
      Dxxx101 = pDMeff101
      Dxxx011 = pDMeff011
      Dxxx111 = pDMeff111
      ! dDyydy 
      Dyyy000 = pDMeff000
      Dyyy100 = pDMeff100
      Dyyy010 = pDMeff010
      Dyyy110 = pDMeff110
      Dyyy001 = pDMeff001
      Dyyy101 = pDMeff101
      Dyyy011 = pDMeff011
      Dyyy111 = pDMeff111
      ! dDzzdz
      Dzzz000 = pDMeff000
      Dzzz100 = pDMeff100
      Dzzz010 = pDMeff010
      Dzzz110 = pDMeff110
      Dzzz001 = pDMeff001
      Dzzz101 = pDMeff101
      Dzzz011 = pDMeff011
      Dzzz111 = pDMeff111
      ! dDxydx
      Dxyx000 = 0d0
      Dxyx100 = 0d0
      Dxyx010 = 0d0
      Dxyx110 = 0d0
      Dxyx001 = 0d0
      Dxyx101 = 0d0
      Dxyx011 = 0d0
      Dxyx111 = 0d0
      ! dDxzdx
      Dxzx000 = 0d0
      Dxzx100 = 0d0
      Dxzx010 = 0d0
      Dxzx110 = 0d0
      Dxzx001 = 0d0
      Dxzx101 = 0d0
      Dxzx011 = 0d0
      Dxzx111 = 0d0
      ! dDxydy
      Dxyy000 = 0d0
      Dxyy100 = 0d0
      Dxyy010 = 0d0
      Dxyy110 = 0d0
      Dxyy001 = 0d0
      Dxyy101 = 0d0
      Dxyy011 = 0d0
      Dxyy111 = 0d0
      ! dDyzdy
      Dyzy000 = 0d0
      Dyzy100 = 0d0
      Dyzy010 = 0d0
      Dyzy110 = 0d0
      Dyzy001 = 0d0
      Dyzy101 = 0d0
      Dyzy011 = 0d0
      Dyzy111 = 0d0
      ! dDxzdz
      Dxzz000 = 0d0
      Dxzz100 = 0d0
      Dxzz010 = 0d0
      Dxzz110 = 0d0
      Dxzz001 = 0d0
      Dxzz101 = 0d0
      Dxzz011 = 0d0
      Dxzz111 = 0d0
      ! dDyzdz
      Dyzz000 = 0d0
      Dyzz100 = 0d0
      Dyzz010 = 0d0
      Dyzz110 = 0d0
      Dyzz001 = 0d0
      Dyzz101 = 0d0
      Dyzz011 = 0d0
      Dyzz111 = 0d0


      if( q000(4) .gt. 0d0 ) then
       Dxxx000 = ( alphaT*q000(4) + pDMeff000 ) + ( aLMinusaT )*q000(1)**2/q000(4)
       Dyyy000 = ( alphaT*q000(4) + pDMeff000 ) + ( aLMinusaT )*q000(2)**2/q000(4)
       Dzzz000 = ( alphaT*q000(4) + pDMeff000 ) + ( aLMinusaT )*q000(3)**2/q000(4)
       Dxyx000 = ( aLMinusaT )*q000(1)*q000(2)/q000(4)
       Dxzx000 = ( aLMinusaT )*q000(1)*q000(3)/q000(4)
       Dxyy000 = ( aLMinusaT )*q000(1)*q000(2)/q000(4)
       Dyzy000 = ( aLMinusaT )*q000(2)*q000(3)/q000(4)
       Dxzz000 = ( aLMinusaT )*q000(1)*q000(3)/q000(4)
       Dyzz000 = ( aLMinusaT )*q000(2)*q000(3)/q000(4)
      end if

      if( q100(4) .gt. 0d0 ) then
       Dxxx100 = ( alphaT*q100(4) + pDMeff100 ) + ( aLMinusaT )*q100(1)**2/q100(4)
       Dyyy100 = ( alphaT*q100(4) + pDMeff100 ) + ( aLMinusaT )*q100(2)**2/q100(4)
       Dzzz100 = ( alphaT*q100(4) + pDMeff100 ) + ( aLMinusaT )*q100(3)**2/q100(4)
       Dxyx100 = ( aLMinusaT )*q100(1)*q100(2)/q100(4)
       Dxzx100 = ( aLMinusaT )*q100(1)*q100(3)/q100(4)
       Dxyy100 = ( aLMinusaT )*q100(1)*q100(2)/q100(4)
       Dyzy100 = ( aLMinusaT )*q100(2)*q100(3)/q100(4)
       Dxzz100 = ( aLMinusaT )*q100(1)*q100(3)/q100(4)
       Dyzz100 = ( aLMinusaT )*q100(2)*q100(3)/q100(4)
      end if

      if( q010(4) .gt. 0d0 ) then
       Dxxx010 = ( alphaT*q010(4) + pDMeff010 ) + ( aLMinusaT )*q010(1)**2/q010(4)
       Dyyy010 = ( alphaT*q010(4) + pDMeff010 ) + ( aLMinusaT )*q010(2)**2/q010(4)
       Dzzz010 = ( alphaT*q010(4) + pDMeff010 ) + ( aLMinusaT )*q010(3)**2/q010(4)
       Dxyx010 = ( aLMinusaT )*q010(1)*q010(2)/q010(4)
       Dxzx010 = ( aLMinusaT )*q010(1)*q010(3)/q010(4)
       Dxyy010 = ( aLMinusaT )*q010(1)*q010(2)/q010(4)
       Dyzy010 = ( aLMinusaT )*q010(2)*q010(3)/q010(4)
       Dxzz010 = ( aLMinusaT )*q010(1)*q010(3)/q010(4)
       Dyzz010 = ( aLMinusaT )*q010(2)*q010(3)/q010(4)
      end if

      if( q110(4) .gt. 0d0 ) then
       Dxxx110 = ( alphaT*q110(4) + pDMeff110 ) + ( aLMinusaT )*q110(1)**2/q110(4)
       Dyyy110 = ( alphaT*q110(4) + pDMeff110 ) + ( aLMinusaT )*q110(2)**2/q110(4)
       Dzzz110 = ( alphaT*q110(4) + pDMeff110 ) + ( aLMinusaT )*q110(3)**2/q110(4)
       Dxyx110 = ( aLMinusaT )*q110(1)*q110(2)/q110(4)
       Dxzx110 = ( aLMinusaT )*q110(1)*q110(3)/q110(4)
       Dxyy110 = ( aLMinusaT )*q110(1)*q110(2)/q110(4)
       Dyzy110 = ( aLMinusaT )*q110(2)*q110(3)/q110(4)
       Dxzz110 = ( aLMinusaT )*q110(1)*q110(3)/q110(4)
       Dyzz110 = ( aLMinusaT )*q110(2)*q110(3)/q110(4)
      end if

      if( q001(4) .gt. 0d0 ) then
       Dxxx001 = ( alphaT*q001(4) + pDMeff001 ) + ( aLMinusaT )*q001(1)**2/q001(4)
       Dyyy001 = ( alphaT*q001(4) + pDMeff001 ) + ( aLMinusaT )*q001(2)**2/q001(4)
       Dzzz001 = ( alphaT*q001(4) + pDMeff001 ) + ( aLMinusaT )*q001(3)**2/q001(4)
       Dxyx001 = ( aLMinusaT )*q001(1)*q001(2)/q001(4)
       Dxzx001 = ( aLMinusaT )*q001(1)*q001(3)/q001(4)
       Dxyy001 = ( aLMinusaT )*q001(1)*q001(2)/q001(4)
       Dyzy001 = ( aLMinusaT )*q001(2)*q001(3)/q001(4)
       Dxzz001 = ( aLMinusaT )*q001(1)*q001(3)/q001(4)
       Dyzz001 = ( aLMinusaT )*q001(2)*q001(3)/q001(4)
      end if

      if( q101(4) .gt. 0d0 ) then
       Dxxx101 = ( alphaT*q101(4) + pDMeff101 ) + ( aLMinusaT )*q101(1)**2/q101(4)
       Dyyy101 = ( alphaT*q101(4) + pDMeff101 ) + ( aLMinusaT )*q101(2)**2/q101(4)
       Dzzz101 = ( alphaT*q101(4) + pDMeff101 ) + ( aLMinusaT )*q101(3)**2/q101(4)
       Dxyx101 = ( aLMinusaT )*q101(1)*q101(2)/q101(4)
       Dxzx101 = ( aLMinusaT )*q101(1)*q101(3)/q101(4)
       Dxyy101 = ( aLMinusaT )*q101(1)*q101(2)/q101(4)
       Dyzy101 = ( aLMinusaT )*q101(2)*q101(3)/q101(4)
       Dxzz101 = ( aLMinusaT )*q101(1)*q101(3)/q101(4)
       Dyzz101 = ( aLMinusaT )*q101(2)*q101(3)/q101(4)
      end if

      if( q011(4) .gt. 0d0 ) then
       Dxxx011 = ( alphaT*q011(4) + pDMeff011 ) + ( aLMinusaT )*q011(1)**2/q011(4)
       Dyyy011 = ( alphaT*q011(4) + pDMeff011 ) + ( aLMinusaT )*q011(2)**2/q011(4)
       Dzzz011 = ( alphaT*q011(4) + pDMeff011 ) + ( aLMinusaT )*q011(3)**2/q011(4)
       Dxyx011 = ( aLMinusaT )*q011(1)*q011(2)/q011(4)
       Dxzx011 = ( aLMinusaT )*q011(1)*q011(3)/q011(4)
       Dxyy011 = ( aLMinusaT )*q011(1)*q011(2)/q011(4)
       Dyzy011 = ( aLMinusaT )*q011(2)*q011(3)/q011(4)
       Dxzz011 = ( aLMinusaT )*q011(1)*q011(3)/q011(4)
       Dyzz011 = ( aLMinusaT )*q011(2)*q011(3)/q011(4)
      end if

      if( q111(4) .gt. 0d0 ) then
       Dxxx111 = ( alphaT*q111(4) + pDMeff111 ) + ( aLMinusaT )*q111(1)**2/q111(4)
       Dyyy111 = ( alphaT*q111(4) + pDMeff111 ) + ( aLMinusaT )*q111(2)**2/q111(4)
       Dzzz111 = ( alphaT*q111(4) + pDMeff111 ) + ( aLMinusaT )*q111(3)**2/q111(4)
       Dxyx111 = ( aLMinusaT )*q111(1)*q111(2)/q111(4)
       Dxzx111 = ( aLMinusaT )*q111(1)*q111(3)/q111(4)
       Dxyy111 = ( aLMinusaT )*q111(1)*q111(2)/q111(4)
       Dyzy111 = ( aLMinusaT )*q111(2)*q111(3)/q111(4)
       Dxzz111 = ( aLMinusaT )*q111(1)*q111(3)/q111(4)
       Dyzz111 = ( aLMinusaT )*q111(2)*q111(3)/q111(4)
      end if


      ! Interpolated derivates !
      call this%TrilinearDerivative( 1, x, y, z, &
                Dxxx000, & 
                Dxxx100, &
                Dxxx010, &
                Dxxx110, &
                Dxxx001, &
                Dxxx101, &
                Dxxx011, &
                Dxxx111, &
                dDxxdx )
      call this%TrilinearDerivative( 2, x, y, z, &
                Dyyy000, &
                Dyyy100, &
                Dyyy010, &
                Dyyy110, &
                Dyyy001, &
                Dyyy101, &
                Dyyy011, &
                Dyyy111, &
                dDyydy )
      call this%TrilinearDerivative( 3, x, y, z, &
                Dzzz000, &
                Dzzz100, &
                Dzzz010, &
                Dzzz110, &
                Dzzz001, &
                Dzzz101, &
                Dzzz011, &
                Dzzz111, &
                dDzzdz )
      call this%TrilinearDerivative( 1, x, y, z, & 
                Dxyx000, & 
                Dxyx100, &
                Dxyx010, &
                Dxyx110, &
                Dxyx001, &
                Dxyx101, &
                Dxyx011, &
                Dxyx111, &
                dDxydx )
      call this%TrilinearDerivative( 1, x, y, z, &
                Dxzx000, &
                Dxzx100, &
                Dxzx010, &
                Dxzx110, &
                Dxzx001, &
                Dxzx101, &
                Dxzx011, &
                Dxzx111, &
                dDxzdx )
      call this%TrilinearDerivative( 2, x, y, z, &
                Dxyy000, &
                Dxyy100, &
                Dxyy010, &
                Dxyy110, &
                Dxyy001, &
                Dxyy101, &
                Dxyy011, &
                Dxyy111, &
                dDxydy )
      call this%TrilinearDerivative( 2, x, y, z, &
                Dyzy000, &
                Dyzy100, &
                Dyzy010, &
                Dyzy110, &
                Dyzy001, &
                Dyzy101, &
                Dyzy011, &
                Dyzy111, &
                dDyzdy )
      call this%TrilinearDerivative( 3, x, y, z, &
                Dxzz000, &
                Dxzz100, &
                Dxzz010, &
                Dxzz110, &
                Dxzz001, &
                Dxzz101, &
                Dxzz011, &
                Dxzz111, &
                dDxzdz )
      call this%TrilinearDerivative( 3, x, y, z, &
                Dyzz000, &
                Dyzz100, &
                Dyzz010, &
                Dyzz110, &
                Dyzz001, &
                Dyzz101, &
                Dyzz011, &
                Dyzz111, &
                dDyzdz )

      ! Notice correction by porosity and retardation 
      divDx = ( dDxxdx + dDxydy + dDxzdz )/this%SubCellData%Porosity/this%SubCellData%Retardation
      divDy = ( dDxydx + dDyydy + dDyzdz )/this%SubCellData%Porosity/this%SubCellData%Retardation
      divDz = ( dDxzdx + dDyzdy + dDzzdz )/this%SubCellData%Porosity/this%SubCellData%Retardation


  end subroutine pr_DispersionDivergenceDischarge


  !! RWPT
  !subroutine pr_DispersionDivergenceDischarge( this, x, y, z, alphaL, alphaT, dMEff, divDx, divDy, divDz )
  !    !----------------------------------------------------------------
  !    ! Compute dispersion divergence terms 
  !    ! 
  !    ! Params:
  !    !     - x, y, z             : local cell coordinates
  !    !     - alphaL              : longidutinal dispersivity
  !    !     - alphaT              : transverse dispersivity
  !    !     - dMEff               : effective molecular diffusion (corrected by tortuosity)
  !    !     - divDx, divDy, divDz : dispersion divergence, output 
  !    !----------------------------------------------------------------
  !    ! Specifications
  !    !----------------------------------------------------------------
  !    implicit none
  !    class (TrackSubCellType)    :: this
  !    ! input
  !    doubleprecision, intent(in) :: x, y, z
  !    doubleprecision, intent(in) :: alphaL, alphaT, dMEff
  !    ! output
  !    doubleprecision, intent(out) :: divDx, divDy, divDz
  !    ! local
  !    doubleprecision, dimension(4) :: v000
  !    doubleprecision, dimension(4) :: v100
  !    doubleprecision, dimension(4) :: v010
  !    doubleprecision, dimension(4) :: v110
  !    doubleprecision, dimension(4) :: v001
  !    doubleprecision, dimension(4) :: v101
  !    doubleprecision, dimension(4) :: v011
  !    doubleprecision, dimension(4) :: v111

  !    doubleprecision :: p000
  !    doubleprecision :: p100
  !    doubleprecision :: p010
  !    doubleprecision :: p110
  !    doubleprecision :: p001
  !    doubleprecision :: p101
  !    doubleprecision :: p011
  !    doubleprecision :: p111


  !    doubleprecision :: D000
  !    doubleprecision :: D100
  !    doubleprecision :: D010
  !    doubleprecision :: D110
  !    doubleprecision :: D001
  !    doubleprecision :: D101
  !    doubleprecision :: D011
  !    doubleprecision :: D111


  !    doubleprecision :: dDxxdx, dDxydy, dDxzdz, &
  !                       dDxydx, dDyydy, dDyzdz, &
  !                       dDxzdx, dDyzdy, dDzzdz
  !    !---------------------------------------------------------------- 

  !    ! Initialize
  !    divDx = 0d0
  !    divDy = 0d0
  !    divDz = 0d0

  !    ! Local copies of SPECIFIC DISCHARGE
  !    ! qx, qy, qz, norm(q)
  !    v000 = this%qCorner000 
  !    v100 = this%qCorner100
  !    v010 = this%qCorner010
  !    v110 = this%qCorner110
  !    v001 = this%qCorner001
  !    v101 = this%qCorner101
  !    v011 = this%qCorner011
  !    v111 = this%qCorner111
  !
  !    ! Porosities
  !    p000 = this%porosity000 
  !    p100 = this%porosity100
  !    p010 = this%porosity010
  !    p110 = this%porosity110
  !    p001 = this%porosity001
  !    p101 = this%porosity101
  !    p011 = this%porosity011
  !    p111 = this%porosity111

  !    ! Is there a more elegant way ? 

  !    ! For X displacement
  !    D000 = p000*dMEff
  !    D100 = p100*dMEff
  !    D010 = p010*dMEff
  !    D110 = p110*dMEff
  !    D001 = p001*dMEff
  !    D101 = p101*dMEff
  !    D011 = p011*dMEff
  !    D111 = p111*dMEff
  !    if( v000(4) .gt. 0d0 ) D000 = ( alphaT*v000(4) + p000*dMEff ) + ( alphaL - alphaT )*v000(1)**2/v000(4)
  !    if( v100(4) .gt. 0d0 ) D100 = ( alphaT*v100(4) + p100*dMEff ) + ( alphaL - alphaT )*v100(1)**2/v100(4)
  !    if( v010(4) .gt. 0d0 ) D010 = ( alphaT*v010(4) + p010*dMEff ) + ( alphaL - alphaT )*v010(1)**2/v010(4)
  !    if( v110(4) .gt. 0d0 ) D110 = ( alphaT*v110(4) + p110*dMEff ) + ( alphaL - alphaT )*v110(1)**2/v110(4)
  !    if( v001(4) .gt. 0d0 ) D001 = ( alphaT*v001(4) + p001*dMEff ) + ( alphaL - alphaT )*v001(1)**2/v001(4)
  !    if( v101(4) .gt. 0d0 ) D101 = ( alphaT*v101(4) + p101*dMEff ) + ( alphaL - alphaT )*v101(1)**2/v101(4)
  !    if( v011(4) .gt. 0d0 ) D011 = ( alphaT*v011(4) + p011*dMEff ) + ( alphaL - alphaT )*v011(1)**2/v011(4)
  !    if( v111(4) .gt. 0d0 ) D111 = ( alphaT*v111(4) + p111*dMEff ) + ( alphaL - alphaT )*v111(1)**2/v111(4)
  !    call this%TrilinearDerivative( 1, x, y, z, &
  !              D000, & 
  !              D100, &
  !              D010, &
  !              D110, &
  !              D001, &
  !              D101, &
  !              D011, &
  !              D111, &
  !              dDxxdx )
  !    ! For Y displacement
  !    D000 = p000*dMEff
  !    D100 = p100*dMEff
  !    D010 = p010*dMEff
  !    D110 = p110*dMEff
  !    D001 = p001*dMEff
  !    D101 = p101*dMEff
  !    D011 = p011*dMEff
  !    D111 = p111*dMEff
  !    if( v000(4) .gt. 0d0 ) D000 = ( alphaT*v000(4) + p000*dMEff ) + ( alphaL - alphaT )*v000(2)**2/v000(4)
  !    if( v100(4) .gt. 0d0 ) D100 = ( alphaT*v100(4) + p100*dMEff ) + ( alphaL - alphaT )*v100(2)**2/v100(4)
  !    if( v010(4) .gt. 0d0 ) D010 = ( alphaT*v010(4) + p010*dMEff ) + ( alphaL - alphaT )*v010(2)**2/v010(4)
  !    if( v110(4) .gt. 0d0 ) D110 = ( alphaT*v110(4) + p110*dMEff ) + ( alphaL - alphaT )*v110(2)**2/v110(4)
  !    if( v001(4) .gt. 0d0 ) D001 = ( alphaT*v001(4) + p001*dMEff ) + ( alphaL - alphaT )*v001(2)**2/v001(4)
  !    if( v101(4) .gt. 0d0 ) D101 = ( alphaT*v101(4) + p101*dMEff ) + ( alphaL - alphaT )*v101(2)**2/v101(4)
  !    if( v011(4) .gt. 0d0 ) D011 = ( alphaT*v011(4) + p011*dMEff ) + ( alphaL - alphaT )*v011(2)**2/v011(4)
  !    if( v111(4) .gt. 0d0 ) D111 = ( alphaT*v111(4) + p111*dMEff ) + ( alphaL - alphaT )*v111(2)**2/v111(4)
  !    call this%TrilinearDerivative( 2, x, y, z, &
  !              D000, &
  !              D100, &
  !              D010, &
  !              D110, &
  !              D001, &
  !              D101, &
  !              D011, &
  !              D111, &
  !              dDyydy )
  !    ! For Z displacement
  !    D000 = p000*dMEff
  !    D100 = p100*dMEff
  !    D010 = p010*dMEff
  !    D110 = p110*dMEff
  !    D001 = p001*dMEff
  !    D101 = p101*dMEff
  !    D011 = p011*dMEff
  !    D111 = p111*dMEff
  !    if( v000(4) .gt. 0d0 ) D000 = ( alphaT*v000(4) + p000*dMEff ) + ( alphaL - alphaT )*v000(3)**2/v000(4)
  !    if( v100(4) .gt. 0d0 ) D100 = ( alphaT*v100(4) + p100*dMEff ) + ( alphaL - alphaT )*v100(3)**2/v100(4)
  !    if( v010(4) .gt. 0d0 ) D010 = ( alphaT*v010(4) + p010*dMEff ) + ( alphaL - alphaT )*v010(3)**2/v010(4)
  !    if( v110(4) .gt. 0d0 ) D110 = ( alphaT*v110(4) + p110*dMEff ) + ( alphaL - alphaT )*v110(3)**2/v110(4)
  !    if( v001(4) .gt. 0d0 ) D001 = ( alphaT*v001(4) + p001*dMEff ) + ( alphaL - alphaT )*v001(3)**2/v001(4)
  !    if( v101(4) .gt. 0d0 ) D101 = ( alphaT*v101(4) + p101*dMEff ) + ( alphaL - alphaT )*v101(3)**2/v101(4)
  !    if( v011(4) .gt. 0d0 ) D011 = ( alphaT*v011(4) + p011*dMEff ) + ( alphaL - alphaT )*v011(3)**2/v011(4)
  !    if( v111(4) .gt. 0d0 ) D111 = ( alphaT*v111(4) + p111*dMEff ) + ( alphaL - alphaT )*v111(3)**2/v111(4)
  !    call this%TrilinearDerivative( 3, x, y, z, &
  !              D000, &
  !              D100, &
  !              D010, &
  !              D110, &
  !              D001, &
  !              D101, &
  !              D011, &
  !              D111, &
  !              dDzzdz )
  !    ! For Y displacement
  !    D000 = 0d0
  !    D100 = 0d0
  !    D010 = 0d0
  !    D110 = 0d0
  !    D001 = 0d0
  !    D101 = 0d0
  !    D011 = 0d0
  !    D111 = 0d0
  !    if( v000(4) .gt. 0d0 ) D000 = ( alphaL - alphaT )*v000(1)*v000(2)/v000(4)
  !    if( v100(4) .gt. 0d0 ) D100 = ( alphaL - alphaT )*v100(1)*v100(2)/v100(4)
  !    if( v010(4) .gt. 0d0 ) D010 = ( alphaL - alphaT )*v010(1)*v010(2)/v010(4)
  !    if( v110(4) .gt. 0d0 ) D110 = ( alphaL - alphaT )*v110(1)*v110(2)/v110(4)
  !    if( v001(4) .gt. 0d0 ) D001 = ( alphaL - alphaT )*v001(1)*v001(2)/v001(4)
  !    if( v101(4) .gt. 0d0 ) D101 = ( alphaL - alphaT )*v101(1)*v101(2)/v101(4)
  !    if( v011(4) .gt. 0d0 ) D011 = ( alphaL - alphaT )*v011(1)*v011(2)/v011(4)
  !    if( v111(4) .gt. 0d0 ) D111 = ( alphaL - alphaT )*v111(1)*v111(2)/v111(4)
  !    call this%TrilinearDerivative( 1, x, y, z, & 
  !              D000, & 
  !              D100, &
  !              D010, &
  !              D110, &
  !              D001, &
  !              D101, &
  !              D011, &
  !              D111, &
  !              dDxydx )
  !    ! For Z displacement
  !    D000 = 0d0
  !    D100 = 0d0
  !    D010 = 0d0
  !    D110 = 0d0
  !    D001 = 0d0
  !    D101 = 0d0
  !    D011 = 0d0
  !    D111 = 0d0
  !    if( v000(4) .gt. 0d0 ) D000 = ( alphaL - alphaT )*v000(1)*v000(3)/v000(4)
  !    if( v100(4) .gt. 0d0 ) D100 = ( alphaL - alphaT )*v100(1)*v100(3)/v100(4)
  !    if( v010(4) .gt. 0d0 ) D010 = ( alphaL - alphaT )*v010(1)*v010(3)/v010(4)
  !    if( v110(4) .gt. 0d0 ) D110 = ( alphaL - alphaT )*v110(1)*v110(3)/v110(4)
  !    if( v001(4) .gt. 0d0 ) D001 = ( alphaL - alphaT )*v001(1)*v001(3)/v001(4)
  !    if( v101(4) .gt. 0d0 ) D101 = ( alphaL - alphaT )*v101(1)*v101(3)/v101(4)
  !    if( v011(4) .gt. 0d0 ) D011 = ( alphaL - alphaT )*v011(1)*v011(3)/v011(4)
  !    if( v111(4) .gt. 0d0 ) D111 = ( alphaL - alphaT )*v111(1)*v111(3)/v111(4)
  !    call this%TrilinearDerivative( 1, x, y, z, &
  !              D000, &
  !              D100, &
  !              D010, &
  !              D110, &
  !              D001, &
  !              D101, &
  !              D011, &
  !              D111, &
  !              dDxzdx )
  !    ! For X displacement
  !    D000 = 0d0
  !    D100 = 0d0
  !    D010 = 0d0
  !    D110 = 0d0
  !    D001 = 0d0
  !    D101 = 0d0
  !    D011 = 0d0
  !    D111 = 0d0
  !    if( v000(4) .gt. 0d0 ) D000 = ( alphaL - alphaT )*v000(1)*v000(2)/v000(4)
  !    if( v100(4) .gt. 0d0 ) D100 = ( alphaL - alphaT )*v100(1)*v100(2)/v100(4)
  !    if( v010(4) .gt. 0d0 ) D010 = ( alphaL - alphaT )*v010(1)*v010(2)/v010(4)
  !    if( v110(4) .gt. 0d0 ) D110 = ( alphaL - alphaT )*v110(1)*v110(2)/v110(4)
  !    if( v001(4) .gt. 0d0 ) D001 = ( alphaL - alphaT )*v001(1)*v001(2)/v001(4)
  !    if( v101(4) .gt. 0d0 ) D101 = ( alphaL - alphaT )*v101(1)*v101(2)/v101(4)
  !    if( v011(4) .gt. 0d0 ) D011 = ( alphaL - alphaT )*v011(1)*v011(2)/v011(4)
  !    if( v111(4) .gt. 0d0 ) D111 = ( alphaL - alphaT )*v111(1)*v111(2)/v111(4)
  !    call this%TrilinearDerivative( 2, x, y, z, &
  !              D000, &
  !              D100, &
  !              D010, &
  !              D110, &
  !              D001, &
  !              D101, &
  !              D011, &
  !              D111, &
  !              dDxydy )
  !    ! For Z displacement
  !    D000 = 0d0
  !    D100 = 0d0
  !    D010 = 0d0
  !    D110 = 0d0
  !    D001 = 0d0
  !    D101 = 0d0
  !    D011 = 0d0
  !    D111 = 0d0
  !    if( v000(4) .gt. 0d0 ) D000 = ( alphaL - alphaT )*v000(2)*v000(3)/v000(4)
  !    if( v100(4) .gt. 0d0 ) D100 = ( alphaL - alphaT )*v100(2)*v100(3)/v100(4)
  !    if( v010(4) .gt. 0d0 ) D010 = ( alphaL - alphaT )*v010(2)*v010(3)/v010(4)
  !    if( v110(4) .gt. 0d0 ) D110 = ( alphaL - alphaT )*v110(2)*v110(3)/v110(4)
  !    if( v001(4) .gt. 0d0 ) D001 = ( alphaL - alphaT )*v001(2)*v001(3)/v001(4)
  !    if( v101(4) .gt. 0d0 ) D101 = ( alphaL - alphaT )*v101(2)*v101(3)/v101(4)
  !    if( v011(4) .gt. 0d0 ) D011 = ( alphaL - alphaT )*v011(2)*v011(3)/v011(4)
  !    if( v111(4) .gt. 0d0 ) D111 = ( alphaL - alphaT )*v111(2)*v111(3)/v111(4)
  !    call this%TrilinearDerivative( 2, x, y, z, &
  !              D000, &
  !              D100, &
  !              D010, &
  !              D110, &
  !              D001, &
  !              D101, &
  !              D011, &
  !              D111, &
  !              dDyzdy )
  !    ! For X displacement
  !    D000 = 0d0
  !    D100 = 0d0
  !    D010 = 0d0
  !    D110 = 0d0
  !    D001 = 0d0
  !    D101 = 0d0
  !    D011 = 0d0
  !    D111 = 0d0
  !    if( v000(4) .gt. 0d0 ) D000 = ( alphaL - alphaT )*v000(1)*v000(3)/v000(4)
  !    if( v100(4) .gt. 0d0 ) D100 = ( alphaL - alphaT )*v100(1)*v100(3)/v100(4)
  !    if( v010(4) .gt. 0d0 ) D010 = ( alphaL - alphaT )*v010(1)*v010(3)/v010(4)
  !    if( v110(4) .gt. 0d0 ) D110 = ( alphaL - alphaT )*v110(1)*v110(3)/v110(4)
  !    if( v001(4) .gt. 0d0 ) D001 = ( alphaL - alphaT )*v001(1)*v001(3)/v001(4)
  !    if( v101(4) .gt. 0d0 ) D101 = ( alphaL - alphaT )*v101(1)*v101(3)/v101(4)
  !    if( v011(4) .gt. 0d0 ) D011 = ( alphaL - alphaT )*v011(1)*v011(3)/v011(4)
  !    if( v111(4) .gt. 0d0 ) D111 = ( alphaL - alphaT )*v111(1)*v111(3)/v111(4)
  !    call this%TrilinearDerivative( 3, x, y, z, &
  !              D000, &
  !              D100, &
  !              D010, &
  !              D110, &
  !              D001, &
  !              D101, &
  !              D011, &
  !              D111, &
  !              dDxzdz )
  !    ! For Y displacement
  !    D000 = 0d0
  !    D100 = 0d0
  !    D010 = 0d0
  !    D110 = 0d0
  !    D001 = 0d0
  !    D101 = 0d0
  !    D011 = 0d0
  !    D111 = 0d0
  !    if( v000(4) .gt. 0d0 ) D000 = ( alphaL - alphaT )*v000(2)*v000(3)/v000(4)
  !    if( v100(4) .gt. 0d0 ) D100 = ( alphaL - alphaT )*v100(2)*v100(3)/v100(4)
  !    if( v010(4) .gt. 0d0 ) D010 = ( alphaL - alphaT )*v010(2)*v010(3)/v010(4)
  !    if( v110(4) .gt. 0d0 ) D110 = ( alphaL - alphaT )*v110(2)*v110(3)/v110(4)
  !    if( v001(4) .gt. 0d0 ) D001 = ( alphaL - alphaT )*v001(2)*v001(3)/v001(4)
  !    if( v101(4) .gt. 0d0 ) D101 = ( alphaL - alphaT )*v101(2)*v101(3)/v101(4)
  !    if( v011(4) .gt. 0d0 ) D011 = ( alphaL - alphaT )*v011(2)*v011(3)/v011(4)
  !    if( v111(4) .gt. 0d0 ) D111 = ( alphaL - alphaT )*v111(2)*v111(3)/v111(4)
  !    call this%TrilinearDerivative( 3, x, y, z, &
  !              D000, &
  !              D100, &
  !              D010, &
  !              D110, &
  !              D001, &
  !              D101, &
  !              D011, &
  !              D111, &
  !              dDyzdz )

  !    ! Notice correction by porosity and retardation 
  !    divDx = ( dDxxdx + dDxydy + dDxzdz )/this%SubCellData%Porosity/this%SubCellData%Retardation
  !    divDy = ( dDxydx + dDyydy + dDyzdz )/this%SubCellData%Porosity/this%SubCellData%Retardation
  !    divDz = ( dDxzdx + dDyzdy + dDzzdz )/this%SubCellData%Porosity/this%SubCellData%Retardation


  !end subroutine pr_DispersionDivergenceDischarge



  subroutine pr_DisplacementRandomDischarge( this, x, y, z, alphaL, alphaT, dMEff, dBx, dBy, dBz ) 
      !----------------------------------------------------------------
      ! Computes the product between displacement matrix and random 
      ! vector
      !
      ! Params:
      !     - x, y, z       : local cell coordinates
      !     - alphaL        : longidutinal dispersivity
      !     - alphaT        : transverse dispersivity
      !     - dMEff         : effective molecular diffusion (corrected by tortuosity )
      !     - dBx, dBy, dBz : random dispersion displacement, output
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class (TrackSubCellType) :: this
      ! input
      doubleprecision, intent(in)    :: x, y, z
      doubleprecision, intent(in)    :: alphaL, alphaT, dMEff
      ! output
      doubleprecision, intent(out) :: dBx, dBy, dBz
      ! local
      doubleprecision :: vBx, vBy, vBz, vBnorm, vBnormxy
      doubleprecision :: B11, B12, B13, B21, B22, B23, B31, B32
      doubleprecision :: rdmx, rdmy, rdmz
      doubleprecision :: RFactor
      doubleprecision, dimension(4) :: v000
      doubleprecision, dimension(4) :: v100
      doubleprecision, dimension(4) :: v010
      doubleprecision, dimension(4) :: v110
      doubleprecision, dimension(4) :: v001
      doubleprecision, dimension(4) :: v101
      doubleprecision, dimension(4) :: v011
      doubleprecision, dimension(4) :: v111
      !----------------------------------------------------------------

      ! Initialize
      dBx = 0d0
      dBy = 0d0
      dBz = 0d0

      ! Local copies of corner velocities
      ! pointers ?
      v000 = this%qCorner000 / this%porosity000 
      v100 = this%qCorner100 / this%porosity100 
      v010 = this%qCorner010 / this%porosity010 
      v110 = this%qCorner110 / this%porosity110 
      v001 = this%qCorner001 / this%porosity001 
      v101 = this%qCorner101 / this%porosity101 
      v011 = this%qCorner011 / this%porosity011 
      v111 = this%qCorner111 / this%porosity111

      ! Extract R
      RFactor = this%SubCellData%Retardation

      ! Trilinear interpolation of velocities and norm
      call this%Trilinear( x, y, z, &
                           v000(1), v100(1), v010(1), v110(1), &
                           v001(1), v101(1), v011(1), v111(1), &
                           vBx )
      call this%Trilinear( x, y, z, &
                           v000(2), v100(2), v010(2), v110(2), &
                           v001(2), v101(2), v011(2), v111(2), &
                           vBy )
      call this%Trilinear( x, y, z, &
                           v000(3), v100(3), v010(3), v110(3), &
                           v001(3), v101(3), v011(3), v111(3), &
                           vBz )
      vBnorm   = sqrt( vBx**2 + vBy**2 + vBz**2 )
      vBnormxy = sqrt( vBx**2 + vBy**2 )
   

      ! Displacement matrix terms
      ! Refs: Fernàndez-Garcia et al. 2005; Salamon et al. 2006
      ! Handles the case of zero vBnorm
      B11 = 0d0 
      B12 = 0d0
      B13 = 0d0
      B21 = 0d0
      B22 = 0d0
      B23 = 0d0
      B31 = 0d0
      B32 = 0d0
      if ( vBnorm .gt. 0d0 ) then
        B11 =       vBx*sqrt( 2*( alphaL*vBnorm + dMEff )/RFactor )/vBnorm
        B21 =       vBy*sqrt( 2*( alphaL*vBnorm + dMEff )/RFactor )/vBnorm
        B31 =       vBz*sqrt( 2*( alphaL*vBnorm + dMEff )/RFactor )/vBnorm
        B32 =  vBnormxy*sqrt( 2*( alphaT*vBnorm + dMEff )/RFactor )/vBnorm
        if ( vBnormxy .gt. 0d0 ) then
          B12 =  -vBx*vBz*sqrt( 2*( alphaT*vBnorm + dMEff )/RFactor )/vBnorm/vBnormxy
          B13 =      -vBy*sqrt( 2*( alphaT*vBnorm + dMEff )/RFactor )/vBnormxy
          B22 =  -vBy*vBz*sqrt( 2*( alphaT*vBnorm + dMEff )/RFactor )/vBnorm/vBnormxy
          B23 =       vBx*sqrt( 2*( alphaT*vBnorm + dMEff )/RFactor )/vBnormxy
        end if
      end if 

      ! Compute random numbers
      call this%GenerateStandardNormalRandom( rdmx ) 
      call this%GenerateStandardNormalRandom( rdmy ) 
      call this%GenerateStandardNormalRandom( rdmz ) 

      ! Compute displacement times random
      dBx = B11*rdmx + B12*rdmy + B13*rdmz 
      dBy = B21*rdmx + B22*rdmy + B23*rdmz 
      dBz = B31*rdmx + B32*rdmy 


  end subroutine pr_DisplacementRandomDischarge


  subroutine pr_DisplacementRandomDischarge2D( this, x, y, z, alphaL, alphaT, dMEff, dBx, dBy, dBz )
      !----------------------------------------------------------------
      ! Computes the product between displacement matrix and random 
      ! vector
      !
      ! Params:
      !     - x, y, z       : local cell coordinates
      !     - alphaL        : longidutinal dispersivity ( assumed for idDim1 )
      !     - alphaT        : transverse dispersivity   ( assumed for idDim2 )
      !     - dMEff         : effective molecular diffusion (corrected by tortuosity )
      !     - dBx, dBy, dBz : random dispersion displacement, output
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class (TrackSubCellType) :: this
      ! input
      doubleprecision, intent(in)    :: x, y, z
      doubleprecision, intent(in)    :: alphaL, alphaT, dMEff
      ! output
      doubleprecision, intent(out) :: dBx, dBy, dBz
      ! local
      doubleprecision :: vB1, vB2, vBnorm
      doubleprecision :: B11, B12, B21, B22
      doubleprecision :: rdm1, rdm2
      doubleprecision :: RFactor
      doubleprecision, dimension(4) :: v000
      doubleprecision, dimension(4) :: v100
      doubleprecision, dimension(4) :: v010
      doubleprecision, dimension(4) :: v110
      doubleprecision, dimension(4) :: v001
      doubleprecision, dimension(4) :: v101
      doubleprecision, dimension(4) :: v011
      doubleprecision, dimension(4) :: v111
      doubleprecision, dimension(3) :: dB
      integer :: idDim1, idDim2
      !----------------------------------------------------------------

      ! Initialize
      dBx    = 0d0
      dBy    = 0d0
      dBz    = 0d0
      dB(:)  = 0d0
      idDim1 = this%dimensions(1)
      idDim2 = this%dimensions(2)

      ! Local copies of corner velocities
      v000 = this%qCorner000 / this%porosity000 
      v100 = this%qCorner100 / this%porosity100 
      v010 = this%qCorner010 / this%porosity010 
      v110 = this%qCorner110 / this%porosity110 
      v001 = this%qCorner001 / this%porosity001 
      v101 = this%qCorner101 / this%porosity101 
      v011 = this%qCorner011 / this%porosity011 
      v111 = this%qCorner111 / this%porosity111

      ! Extract R
      RFactor = this%SubCellData%Retardation

      ! Trilinear interpolation of velocities and norm
      call this%Trilinear( x, y, z, &
                           v000(idDim1), v100(idDim1), v010(idDim1), v110(idDim1), &
                           v001(idDim1), v101(idDim1), v011(idDim1), v111(idDim1), &
                           vB1 )
      call this%Trilinear( x, y, z, &
                           v000(idDim2), v100(idDim2), v010(idDim2), v110(idDim2), &
                           v001(idDim2), v101(idDim2), v011(idDim2), v111(idDim2), &
                           vB2 )
      vBnorm   = sqrt( vB1**2 + vB2**2 )

      ! Displacement matrix terms
      ! Refs: Fernàndez-Garcia et al. 2005; Salamon et al. 2006
      ! Handles the case of zero vBnorm
      B11 = 0d0 
      B12 = 0d0
      B21 = 0d0
      B22 = 0d0
      if ( vBnorm .gt. 0d0 ) then
        B11 =  vB1*sqrt( 2*( alphaL*vBnorm + dMEff )/RFactor )/vBnorm
        B21 =  vB2*sqrt( 2*( alphaL*vBnorm + dMEff )/RFactor )/vBnorm
        B12 = -vB2*sqrt( 2*( alphaT*vBnorm + dMEff )/RFactor )/vBnorm
        B22 =  vB1*sqrt( 2*( alphaT*vBnorm + dMEff )/RFactor )/vBnorm
      end if 

      ! Compute random numbers
      call this%GenerateStandardNormalRandom( rdm1 ) 
      call this%GenerateStandardNormalRandom( rdm2 )

      ! Compute displacement times random
      dB(idDim1) = B11*rdm1 + B12*rdm2
      dB(idDim2) = B21*rdm1 + B22*rdm2

      dBx = dB(1)
      dBy = dB(2)
      dBz = dB(3)


  end subroutine pr_DisplacementRandomDischarge2D


  subroutine pr_DisplacementRandomDischarge1D( this, x, y, z, alphaL, alphaT, dMEff, dBx, dBy, dBz )
      !----------------------------------------------------------------
      ! Computes the product between displacement matrix and random 
      ! vector
      !
      ! Params:
      !     - x, y, z       : local cell coordinates
      !     - alphaL        : longidutinal dispersivity ( assumed for idDim1 )
      !     - alphaT        : transverse dispersivity   ( not used )
      !     - dMEff         : effective molecular diffusion (corrected by tortuosity )
      !     - dBx, dBy, dBz : random dispersion displacement, output
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class (TrackSubCellType) :: this
      ! input
      doubleprecision, intent(in)    :: x, y, z
      doubleprecision, intent(in)    :: alphaL, alphaT, dMEff
      ! output
      doubleprecision, intent(out) :: dBx, dBy, dBz
      ! local
      doubleprecision :: vB1, vBnorm
      doubleprecision :: B11
      doubleprecision :: rdm1
      doubleprecision :: RFactor
      doubleprecision, dimension(4) :: v000
      doubleprecision, dimension(4) :: v100
      doubleprecision, dimension(4) :: v010
      doubleprecision, dimension(4) :: v110
      doubleprecision, dimension(4) :: v001
      doubleprecision, dimension(4) :: v101
      doubleprecision, dimension(4) :: v011
      doubleprecision, dimension(4) :: v111
      doubleprecision, dimension(3) :: dB
      integer :: idDim1
      !----------------------------------------------------------------

      ! Initialize
      dBx    = 0d0
      dBy    = 0d0
      dBz    = 0d0
      dB(:)  = 0d0
      idDim1 = this%dimensions(1)

      ! Local copies of corner velocities
      v000 = this%qCorner000 / this%porosity000 
      v100 = this%qCorner100 / this%porosity100 
      v010 = this%qCorner010 / this%porosity010 
      v110 = this%qCorner110 / this%porosity110 
      v001 = this%qCorner001 / this%porosity001 
      v101 = this%qCorner101 / this%porosity101 
      v011 = this%qCorner011 / this%porosity011 
      v111 = this%qCorner111 / this%porosity111

      ! Extract R
      RFactor = this%SubCellData%Retardation

      ! Trilinear interpolation of velocities and norm
      call this%Trilinear( x, y, z, &
                           v000(idDim1), v100(idDim1), v010(idDim1), v110(idDim1), &
                           v001(idDim1), v101(idDim1), v011(idDim1), v111(idDim1), &
                           vB1 )
      vBnorm = sqrt(vB1**2)

      ! Displacement matrix terms
      ! Refs: Fernàndez-Garcia et al. 2005; Salamon et al. 2006
      ! Handles the case of zero vBnorm
      B11 = 0d0 
      if ( vBnorm .gt. 0d0 ) B11 = sqrt( 2*( alphaL*vBnorm + dMEff )/RFactor )

      ! Compute random numbers
      call this%GenerateStandardNormalRandom( rdm1 ) 

      ! Compute displacement times random
      dB(idDim1) = B11*rdm1

      dBx = dB(1)
      dBy = dB(2)
      dBz = dB(3)


  end subroutine pr_DisplacementRandomDischarge1D





  ! RWPT
  subroutine pr_GenerateStandardNormalRandom( this, random_value )
      !----------------------------------------------------------------
      ! Generate a random number from an standard normal distribution
      ! Inherited from RW3D:library_gslib:random_normal
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class(TrackSubCellType) :: this 
      ! input/output
      doubleprecision, intent(out) :: random_value
      ! local
      doubleprecision :: harvest(12)
      !----------------------------------------------------------------

      call random_number (harvest)
      random_value = sum(harvest)-6.d0

      return

  end subroutine  pr_GenerateStandardNormalRandom


  ! RWPT
  subroutine pr_ComputeCornerVariables( this, currentCellData, neighborCellData )
  !----------------------------------------------------------------
  !
  !----------------------------------------------------------------
  ! Specifications
  !----------------------------------------------------------------
  implicit none
  class(TrackSubCellType) :: this
  type(ModpathCellDataType) :: currentCellData
  type(ModpathCellDataType), dimension(2,18) :: neighborCellData
  integer, dimension(3,18)         :: neighborSubCellIndexes   ! nbcell, subRow, subColumn
  doubleprecision, dimension(6,18) :: neighborSubCellFaceFlows ! nbcell, flowFaceNumber
  doubleprecision, dimension(3,18) :: neighborSubCellFaceAreas ! nbcell, faceDirection
  doubleprecision, dimension(18)   :: neighborSubCellVolume   
  doubleprecision, dimension(18)   :: neighborSubCellPorosity 
  !----------------------------------------------------------------
  
    ! Get sub cell indexes for current sub cell location
    neighborSubCellIndexes = currentCellData%GetNeighborSubCellIndexes( &
                           this%SubCellData%Row, this%SubCellData%Column )

    ! Fill neighbor cells faceFlows
    call pr_FillNeighborSubCellVariables( this, currentCellData, neighborCellData, &
       neighborSubCellIndexes, neighborSubCellFaceFlows, neighborSubCellFaceAreas, &
                                    neighborSubCellVolume, neighborSubCellPorosity )
    ! Compute discharge
    call pr_ComputeCornerDischarge( this, currentCellData, & 
        neighborSubCellFaceFlows, neighborSubCellFaceAreas )

    ! Compute porosities
    call pr_ComputeCornerPorosity( this, neighborSubCellVolume, neighborSubCellPorosity )

    ! Done
    return


  end subroutine pr_ComputeCornerVariables


  ! RWPT
  ! Could be differentiated for usg vs structured to avoid getsubcellcount if check 
  subroutine pr_FillNeighborSubCellVariables( this, centerCellData, neighborCellData, &
          neighborSubCellIndexes, neighborSubCellFaceFlows, neighborSubCellFaceAreas, & 
                                      neighborSubCellVolume, neighborSubCellPorosity  )
      !-----------------------------------------------------------
      !
      !-----------------------------------------------------------
      ! Specifications
      !-----------------------------------------------------------
      implicit none
      class (TrackSubCellType) :: this
      class (ModpathCellDataType), intent(in) :: centerCellData 
      class (ModpathCellDataType), dimension(2,18), intent(in) :: neighborCellData 
      integer, dimension(3,18), intent(in) ::  neighborSubCellIndexes ! nCellBuffer, subRow, subCol
      doubleprecision, dimension(6,18), intent(out) :: neighborSubCellFaceFlows ! faceFlows
      doubleprecision, dimension(3,18), intent(out) :: neighborSubCellFaceAreas ! faceAreas
      doubleprecision, dimension(18)  , intent(out) :: neighborSubCellVolume    ! volumes
      doubleprecision, dimension(18)  , intent(out) :: neighborSubCellPorosity  ! porosities
      logical :: skipSubCells = .false.
      integer :: subConnectionIndex, neighborSubRow, neighborSubColumn
      integer :: n
      !-----------------------------------------------------------


      ! Reset arrays
      neighborSubCellFaceFlows = 0d0
      neighborSubCellFaceAreas = 0d0
      neighborSubCellVolume    = 0d0
      neighborSubCellPorosity  = 0d0


      ! If current cell is not refined
      if ( centerCellData%GetSubCellCount() .eq. 1 ) then 
          ! Cell is not refined then neighbors
          ! have the same size, some maybe refined
          ! due to connections with smaller cells.
          ! Skip sub cell indexation in such case. 
          skipSubCells = .true.
          do n = 1,18

              if ( neighborCellData( 1, neighborSubCellIndexes( 1, n ) )%CellNumber .eq. 0 ) cycle

              call neighborCellData( &
                  1, neighborSubCellIndexes( 1, n ) )%FillSubCellFaceFlows( 1, 1, &
                                    neighborSubCellFaceFlows( :, n ), skipSubCells )
              call neighborCellData( & 
                  1, neighborSubCellIndexes( 1, n ) )%FillSubCellFaceAreas( neighborSubCellFaceAreas( :, n ), skipSubCells ) 

              neighborSubCellVolume(n)   = neighborCellData( 1, neighborSubCellIndexes( 1, n ) )%GetVolume( skipSubCells )
              neighborSubCellPorosity(n) = neighborCellData( 1, neighborSubCellIndexes( 1, n ) )%Porosity

          end do

          ! Done 
          return

      end if  


      ! If current cell is refined
      do n = 1, 18
          skipSubCells = .false.

          ! Fill face flows with one of its own subcells
          if ( neighborSubCellIndexes( 1, n ) .eq. 0 ) then
              call centerCellData%FillSubCellFaceFlowsBuffer( &
                                neighborSubCellIndexes( 2, n ), neighborSubCellIndexes( 3, n ), & 
                                                               neighborSubCellFaceFlows( :, n ) )

              call centerCellData%FillSubCellFaceAreas( neighborSubCellFaceAreas( :, n ), skipSubCells )

              neighborSubCellVolume(n)   = centerCellData%GetVolume( skipSubCells )
              neighborSubCellPorosity(n) = centerCellData%Porosity

              cycle

          end if

          ! Fill face flows with data obtained from neighbors
          if ( neighborCellData( 2, neighborSubCellIndexes( 1, n ) )%CellNumber .gt. 0 ) then
              ! If double buffer 

              ! When the buffer is double, 
              ! these cells are smaller, then skip 
              ! sub cell indexation if refined. 
              if ( & 
                  ( neighborCellData(1, neighborSubCellIndexes( 1, n ) )%GetSubCellCount() .gt. 1 ) .or. &
                  ( neighborCellData(2, neighborSubCellIndexes( 1, n ) )%GetSubCellCount() .gt. 1 ) ) then 
                  skipSubCells = .true.
              end if 

              ! Detect from which direction where requested.
              if ( neighborCellData( 2, neighborSubCellIndexes( 1, n ) )%requestedFromDirection .eq. 1 ) then 
                  ! If x-direction, location in buffer is given by subcell row index 
                  subConnectionIndex = neighborSubCellIndexes( 2, n )
                  neighborSubRow     = 1 
                  neighborSubColumn  = 1
              else if ( neighborCellData( 2, neighborSubCellIndexes( 1, n ) )%requestedFromDirection .eq. 2 ) then
                  ! If y-direction, location in buffer is given by subcell column index 
                  subConnectionIndex = neighborSubCellIndexes( 3, n )
                  neighborSubRow     = 1 
                  neighborSubColumn  = 1
              else 
                  ! If z-direction, location in buffer is also given 
                  ! by subcell column index. This is true because double 
                  ! buffers requested from a vertical face are possible 
                  ! only if horizontal buffer is double too. This means 
                  ! that this case is related to indirect buffers, which 
                  ! in the current protocol of neighbor cells initialization 
                  ! are only possible after initialization of a direct connection 
                  ! through the y-direction. 
                  subConnectionIndex = neighborSubCellIndexes( 3, n )
                  neighborSubRow     = 1 
                  neighborSubColumn  = 1
              end if 

          else if ( &
              ( neighborCellData( 1, neighborSubCellIndexes( 1, n ) )%CellNumber .gt. 0 ) .or. & 
              ( neighborCellData( 1, neighborSubCellIndexes( 1, n ) )%fromSubCell ) ) then
              ! If single buffer 

              if ( neighborCellData(1, neighborSubCellIndexes( 1, n ) )%GetSubCellCount() .gt. 1 ) then 
                  ! If its refined request the sub cell indexes
                  subConnectionIndex = 1
                  neighborSubRow     = neighborSubCellIndexes( 2, n )
                  neighborSubColumn  = neighborSubCellIndexes( 3, n ) 
              else
                  ! If its not refined, all ones
                  subConnectionIndex = 1
                  neighborSubRow     = 1
                  neighborSubColumn  = 1
              end if

          else
              ! Buffer is empty, continue
              cycle
          end if  

          ! Fill variables 
          call neighborCellData( subConnectionIndex, neighborSubCellIndexes( 1, n ) )%FillSubCellFaceFlows( &
                          neighborSubRow, neighborSubColumn, neighborSubCellFaceFlows( :, n ), skipSubCells )

          call neighborCellData( subConnectionIndex, neighborSubCellIndexes( 1, n ) )%FillSubCellFaceAreas( &
                                                             neighborSubCellFaceAreas( :, n ), skipSubCells )  

          neighborSubCellVolume(n)   = neighborCellData(&
              subConnectionIndex, neighborSubCellIndexes( 1, n ) )%GetVolume( skipSubCells )
          neighborSubCellPorosity(n) = neighborCellData(&
              subConnectionIndex, neighborSubCellIndexes( 1, n ) )%Porosity

      end do


      ! Done
      return


  end subroutine pr_FillNeighborSubCellVariables


  ! RWPT
  subroutine pr_ComputeCornerDischarge( this, currentCellData, &
            neighborSubCellFaceFlows, neighborSubCellFaceAreas )
  !----------------------------------------------------------------
  !----------------------------------------------------------------
  ! Specifications
  !----------------------------------------------------------------
  implicit none
  class(TrackSubCellType) :: this
  ! input
  type(ModpathCellDataType) :: currentCellData
  doubleprecision, dimension(6,18), intent(in) :: neighborSubCellFaceFlows ! nbcell, flowFaceNumber
  doubleprecision, dimension(3,18), intent(in) :: neighborSubCellFaceAreas ! nbcell, faceDirection
  ! local
  doubleprecision, dimension(6) :: centerSubCellFaceFlows
  integer :: n
  !----------------------------------------------------------------


      ! Fill faceFlows from current subcell
      call currentCellData%FillSubCellFaceFlowsBuffer( &
          this%SubCellData%Row, this%SubCellData%Column, centerSubCellFaceFlows )

      ! For each dimension
      ! dimension mask ?
       do n = 1, 3
           this%qCorner000(n) = this%GetInterpolatedCornerDischarge( & 
                centerSubCellFaceFlows, neighborSubCellFaceFlows, neighborSubCellFaceAreas, 1, n ) 
           this%qCorner100(n) = this%GetInterpolatedCornerDischarge( & 
                centerSubCellFaceFlows, neighborSubCellFaceFlows, neighborSubCellFaceAreas, 2, n ) 
           this%qCorner010(n) = this%GetInterpolatedCornerDischarge( & 
                centerSubCellFaceFlows, neighborSubCellFaceFlows, neighborSubCellFaceAreas, 3, n ) 
           this%qCorner110(n) = this%GetInterpolatedCornerDischarge( & 
                centerSubCellFaceFlows, neighborSubCellFaceFlows, neighborSubCellFaceAreas, 4, n ) 
           this%qCorner001(n) = this%GetInterpolatedCornerDischarge( & 
                centerSubCellFaceFlows, neighborSubCellFaceFlows, neighborSubCellFaceAreas, 5, n ) 
           this%qCorner101(n) = this%GetInterpolatedCornerDischarge( & 
                centerSubCellFaceFlows, neighborSubCellFaceFlows, neighborSubCellFaceAreas, 6, n ) 
           this%qCorner011(n) = this%GetInterpolatedCornerDischarge( & 
                centerSubCellFaceFlows, neighborSubCellFaceFlows, neighborSubCellFaceAreas, 7, n ) 
           this%qCorner111(n) = this%GetInterpolatedCornerDischarge( & 
                centerSubCellFaceFlows, neighborSubCellFaceFlows, neighborSubCellFaceAreas, 8, n ) 
       end do 

      ! Norm
      this%qCorner000(4) = sqrt( this%qCorner000(1)**2 + this%qCorner000(2)**2 + this%qCorner000(3)**2 )
      this%qCorner100(4) = sqrt( this%qCorner100(1)**2 + this%qCorner100(2)**2 + this%qCorner100(3)**2 )
      this%qCorner010(4) = sqrt( this%qCorner010(1)**2 + this%qCorner010(2)**2 + this%qCorner010(3)**2 )
      this%qCorner110(4) = sqrt( this%qCorner110(1)**2 + this%qCorner110(2)**2 + this%qCorner110(3)**2 )
      this%qCorner001(4) = sqrt( this%qCorner001(1)**2 + this%qCorner001(2)**2 + this%qCorner001(3)**2 )
      this%qCorner101(4) = sqrt( this%qCorner101(1)**2 + this%qCorner101(2)**2 + this%qCorner101(3)**2 )
      this%qCorner011(4) = sqrt( this%qCorner011(1)**2 + this%qCorner011(2)**2 + this%qCorner011(3)**2 )
      this%qCorner111(4) = sqrt( this%qCorner111(1)**2 + this%qCorner111(2)**2 + this%qCorner111(3)**2 )


  end subroutine pr_ComputeCornerDischarge



  ! RWPT
  function pr_GetInterpolatedCornerDischarge( this, centerSubCellFaceFlows, &
                        neighborSubCellFaceFlows, neighborSubCellFaceAreas, & 
                                                cornerIndex, faceDirection  ) result( qCorner )
  !---------------------------------------------------------------------
  ! Compute interpolated corner discharge as the sum of flow rates
  ! of contributing faces divided by the sum of face areas
  !
  ! Initializes sums with contribution of center cell and 
  ! loop over remaining involved cells
  !---------------------------------------------------------------------
  implicit none
  class( TrackSubCellType ) :: this
  ! input
  doubleprecision, dimension(6)   , intent(in) :: centerSubCellFaceFlows 
  doubleprecision, dimension(6,18), intent(in) :: neighborSubCellFaceFlows
  doubleprecision, dimension(3,18), intent(in) :: neighborSubCellFaceAreas
  integer, intent(in) :: cornerIndex, faceDirection
  ! local
  doubleprecision :: sumArea, sumFlowRate = 0d0
  integer :: m 
  ! output 
  doubleprecision :: qCorner    
  !---------------------------------------------------------------------
  
    
     select case( faceDirection ) 
       case (1) 
         sumArea     = this%SubCellData%DY*this%SubCellData%DZ
         sumFlowRate = centerSubCellFaceFlows( this%cornerXComponentIndexes( cornerIndex, 4 ) )
         do m = 1, 3
           sumArea = sumArea + &
               neighborSubCellFaceAreas( 1, this%cornerXComponentIndexes( cornerIndex, m ) )
           sumFlowRate = sumFlowRate + & 
               neighborSubCellFaceFlows( this%cornerXComponentIndexes( cornerIndex, 4 ) , &
                                         this%cornerXComponentIndexes( cornerIndex, m ) )  
         end do
       case (2)
         sumArea     = this%SubCellData%DX*this%SubCellData%DZ
         sumFlowRate = centerSubCellFaceFlows( this%cornerYComponentIndexes( cornerIndex, 4 ) )
         do m = 1, 3
           sumArea = sumArea + &
               neighborSubCellFaceAreas( 2, this%cornerYComponentIndexes( cornerIndex, m ) )
           sumFlowRate = sumFlowRate + & 
               neighborSubCellFaceFlows( this%cornerYComponentIndexes( cornerIndex, 4 ) , &
                                         this%cornerYComponentIndexes( cornerIndex, m ) )  
         end do
       case (3)
         sumArea     = this%SubCellData%DX*this%SubCellData%DY
         sumFlowRate = centerSubCellFaceFlows( this%cornerZComponentIndexes( cornerIndex, 4 ) )
         do m = 1, 3
           sumArea = sumArea + &
               neighborSubCellFaceAreas( 3, this%cornerZComponentIndexes( cornerIndex, m ) )
           sumFlowRate = sumFlowRate + & 
               neighborSubCellFaceFlows( this%cornerZComponentIndexes( cornerIndex, 4 ) , &
                                         this%cornerZComponentIndexes( cornerIndex, m ) )  
         end do
     end select 
 

     ! flowContributionFactor=0.25 is cancelled implicitly    
     qCorner = sumFlowRate/sumArea
  
  
  end function pr_GetInterpolatedCornerDischarge



  subroutine pr_SetCornerComponentsIndexes( this ) 
      !-----------------------------------------------------------------
      ! Set neighbor sub cells indexes for computation of 
      ! x,y,z components of corner quantities
      ! 
      ! Convention for sub cell corners
      !     1: 000
      !     2: 100
      !     3: 010
      !     4: 110
      !     5: 001
      !     6: 101
      !     7: 011
      !     8: 111
      !
      ! dev: find a proper place for doing this only once
      !-----------------------------------------------------------------
      implicit none
      class( TrackSubCellType ) :: this
      !-----------------------------------------------------------------


      ! Cell indexes for x-component
      ! 000: 7-8-13   : fn1 : 
      ! 100: 7-8-13   : fn2 : 
      ! 010: 10-11-13 : fn1 : 
      ! 110: 10-11-13 : fn2 :  
      ! 001: 7-9-16   : fn1 :
      ! 101: 7-9-16   : fn2 :
      ! 011: 10-12-16 : fn1 :
      ! 111: 10-12-16 : fn2 :
      this%cornerXComponentIndexes(1,:) = [ 7, 8,13,1] 
      this%cornerXComponentIndexes(2,:) = [ 7, 8,13,2] 
      this%cornerXComponentIndexes(3,:) = [10,11,13,1] 
      this%cornerXComponentIndexes(4,:) = [10,11,13,2] 
      this%cornerXComponentIndexes(5,:) = [ 7, 9,16,1] 
      this%cornerXComponentIndexes(6,:) = [ 7, 9,16,2] 
      this%cornerXComponentIndexes(7,:) = [10,12,16,1] 
      this%cornerXComponentIndexes(8,:) = [10,12,16,2] 


      ! Cell indexes for y-component
      !000: 1-13-14 : fn3 :
      !100: 4-13-15 : fn3 :
      !010: 1-13-14 : fn4 :
      !110: 4-13-15 : fn4 :
      !001: 1-16-17 : fn3 :
      !101: 4-16-18 : fn3 :
      !011: 1-16-17 : fn4 :
      !111: 4-16-18 : fn4 :
      this%cornerYComponentIndexes(1,:) = [ 1,13,14,3] 
      this%cornerYComponentIndexes(2,:) = [ 4,13,15,3] 
      this%cornerYComponentIndexes(3,:) = [ 1,13,14,4] 
      this%cornerYComponentIndexes(4,:) = [ 4,13,15,4] 
      this%cornerYComponentIndexes(5,:) = [ 1,16,17,3] 
      this%cornerYComponentIndexes(6,:) = [ 4,16,18,3] 
      this%cornerYComponentIndexes(7,:) = [ 1,16,17,4] 
      this%cornerYComponentIndexes(8,:) = [ 4,16,18,4]


      ! Cell indexes for z-component
      !000: 1-2-7   : fn5 :
      !100: 4-5-7   : fn5 :
      !010: 1-3-10  : fn5 :
      !110: 4-6-10  : fn5 :
      !001: 1-2-7   : fn6 :
      !101: 4-5-7   : fn6 :
      !011: 1-3-10  : fn6 :
      !111: 4-6-10  : fn6 :
      this%cornerZComponentIndexes(1,:) = [ 1, 2, 7,5] 
      this%cornerZComponentIndexes(2,:) = [ 4, 5, 7,5] 
      this%cornerZComponentIndexes(3,:) = [ 1, 3,10,5] 
      this%cornerZComponentIndexes(4,:) = [ 4, 6,10,5] 
      this%cornerZComponentIndexes(5,:) = [ 1, 2, 7,6] 
      this%cornerZComponentIndexes(6,:) = [ 4, 5, 7,6] 
      this%cornerZComponentIndexes(7,:) = [ 1, 3,10,6] 
      this%cornerZComponentIndexes(8,:) = [ 4, 6,10,6]


      return


  end subroutine pr_SetCornerComponentsIndexes



  ! RWPT
  subroutine pr_ComputeCornerPorosity( this, neighborSubCellVolume, neighborSubCellPorosity )
      !----------------------------------------------------------------
      ! From its subCellData and neighborSubCellData array, 
      ! computes velocities at cell corners
      !
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class( TrackSubCellType ) :: this
      ! input
      doubleprecision, dimension(18), intent(in) :: neighborSubCellVolume   
      doubleprecision, dimension(18), intent(in) :: neighborSubCellPorosity
      !-----------------------------------------------------------------

      ! If spatially variable porosity, something to identify ?

      ! Assign interpolated values
      this%porosity000 = this%GetInterpolatedCornerPorosity( neighborSubCellVolume, neighborSubCellPorosity, 1 )
      this%porosity100 = this%GetInterpolatedCornerPorosity( neighborSubCellVolume, neighborSubCellPorosity, 2 )
      this%porosity010 = this%GetInterpolatedCornerPorosity( neighborSubCellVolume, neighborSubCellPorosity, 3 )
      this%porosity110 = this%GetInterpolatedCornerPorosity( neighborSubCellVolume, neighborSubCellPorosity, 4 )
      this%porosity001 = this%GetInterpolatedCornerPorosity( neighborSubCellVolume, neighborSubCellPorosity, 5 )
      this%porosity101 = this%GetInterpolatedCornerPorosity( neighborSubCellVolume, neighborSubCellPorosity, 6 )
      this%porosity011 = this%GetInterpolatedCornerPorosity( neighborSubCellVolume, neighborSubCellPorosity, 7 )
      this%porosity111 = this%GetInterpolatedCornerPorosity( neighborSubCellVolume, neighborSubCellPorosity, 8 )

        
      !! This is the fallback for spatially 
      !! constant porosity
      !this%porosity000 = this%SubCellData%Porosity   
      !this%porosity100 = this%SubCellData%Porosity
      !this%porosity010 = this%SubCellData%Porosity       
      !this%porosity110 = this%SubCellData%Porosity
      !this%porosity001 = this%SubCellData%Porosity
      !this%porosity101 = this%SubCellData%Porosity       
      !this%porosity011 = this%SubCellData%Porosity
      !this%porosity111 = this%SubCellData%Porosity


      return

      
  end subroutine pr_ComputeCornerPorosity


  ! RWPT-USG
  function pr_GetInterpolatedCornerPorosity( this, neighborSubCellVolume, &
                                     neighborSubCellPorosity, cornerIndex ) result( cornerPorosity ) 
  !-------------------------------------------------------------------------
  ! Compute equivalent corner porosity for a given cornerIndex, 
  ! using source information in neighborSubCellVolume and 
  ! neighborSubCellPorosity
  !
  ! Equivalent corner porosity is a volume weighted average
  ! between 7 cells: 6 neighbors and center cell
  !-------------------------------------------------------------------------
  implicit none
  class( TrackSubCellType ) :: this
  ! input
  doubleprecision, dimension(18), intent(in) :: neighborSubCellVolume
  doubleprecision, dimension(18), intent(in) :: neighborSubCellPorosity
  integer, intent(in) :: cornerIndex
  ! output
  doubleprecision     :: cornerPorosity
  ! local 
  doubleprecision :: sumVolume, sumWeightedPorosity
  integer :: m
  !------------------------------------------------------------------------


      sumVolume           = this%SubCellData%DX*this%SubCellData%DY*this%SubCellData%DZ
      sumWeightedPorosity = this%SubCellData%Porosity*sumVolume
      do m = 1, 6
          sumVolume = sumVolume + &
              neighborSubCellVolume( this%cornerPorosityIndexes( cornerIndex, m ) )
          sumWeightedPorosity = sumWeightedPorosity + & 
              neighborSubCellVolume( this%cornerPorosityIndexes( cornerIndex, m ) )*&
              neighborSubCellPorosity( this%cornerPorosityIndexes( cornerIndex, m ) ) 
      end do

      cornerPorosity = sumWeightedPorosity/sumVolume

      return


  end function pr_GetInterpolatedCornerPorosity



  subroutine pr_SetCornerPorosityIndexes( this ) 
      !-----------------------------------------------------------------
      ! Set neighbor sub cells indexes for computation of 
      ! equivalent corner porosities
      ! 
      ! Convention for sub cell corners
      !     1: 000
      !     2: 100
      !     3: 010
      !     4: 110
      !     5: 001
      !     6: 101
      !     7: 011
      !     8: 111
      !
      ! dev: find a proper place for doing this only once
      !-----------------------------------------------------------------
      implicit none
      class( TrackSubCellType ) :: this
      !-----------------------------------------------------------------


      ! Cell indexes for corner porosity
      this%cornerPorosityIndexes(1,:) = [ 1, 2,  7,  8, 13, 14 ]
      this%cornerPorosityIndexes(2,:) = [ 4, 5,  7,  8, 13, 15 ]
      this%cornerPorosityIndexes(3,:) = [ 1, 3, 10, 11, 13, 14 ]
      this%cornerPorosityIndexes(4,:) = [ 4, 6, 10, 12, 16, 18 ]
      this%cornerPorosityIndexes(5,:) = [ 1, 2,  7,  9, 16, 17 ]
      this%cornerPorosityIndexes(6,:) = [ 4, 5,  7,  9, 16, 18 ]
      this%cornerPorosityIndexes(7,:) = [ 1, 3, 10, 12, 16, 17 ]
      this%cornerPorosityIndexes(8,:) = [ 4, 6, 10, 11, 13, 15 ]


      return


  end subroutine pr_SetCornerPorosityIndexes



  ! RWPT
  subroutine pr_TrilinearDerivative( this, direction, x, y, z, v000, v100, v010, v110, v001, v101, v011, v111, output )
      !-----------------------------------------------------------
      ! Compute derivative of a trilinear interpolation in a given
      ! direction
      ! 
      ! Params
      !     - x, y, z   : local cell coordinates 
      !     - direction : specifies x=1, y=2 or z=3 direction
      !     - vijk      : values at corresponding corners
      !     - output    : the output variable
      !-----------------------------------------------------------
      ! Specifications
      !-----------------------------------------------------------
      implicit none
      class (TrackSubCellType) :: this
      ! input
      integer        , intent(in):: direction
      doubleprecision, intent(in):: x, y, z
      doubleprecision, intent(in):: v000, v100, v010, v110, v001, v101, v011, v111
      ! output
      doubleprecision, intent(inout) :: output
      ! local
      doubleprecision :: v0, v1, v00, v10, v01, v11
      !-----------------------------------------------------------

      ! Initialize
      output = 0d0

      select case (direction)
          ! x direction
          case (1)
              v00    = ( v100 - v000 )/this%SubCellData%DX
              v01    = ( v101 - v001 )/this%SubCellData%DX
              v10    = ( v110 - v010 )/this%SubCellData%DX
              v11    = ( v111 - v011 )/this%SubCellData%DX
              v0     = ( 1.0d0 - y )*v00 + y*v10
              v1     = ( 1.0d0 - y )*v01 + y*v11
              output = ( 1.0d0 - z )*v0  + z*v1 
              return 
          ! y direction
          case (2)
              v00    = ( v010 - v000 )/this%SubCellData%DY
              v01    = ( v011 - v001 )/this%SubCellData%DY
              v10    = ( v110 - v100 )/this%SubCellData%DY
              v11    = ( v111 - v101 )/this%SubCellData%DY
              v0     = ( 1.0d0 - x )*v00 + x*v10
              v1     = ( 1.0d0 - x )*v01 + x*v11
              output = ( 1.0d0 - z )*v0  + z*v1 
              return 
          ! z direction
          case (3) 
              v00    = ( v001 - v000 )/this%SubCellData%DZ
              v01    = ( v011 - v010 )/this%SubCellData%DZ
              v10    = ( v101 - v100 )/this%SubCellData%DZ
              v11    = ( v111 - v110 )/this%SubCellData%DZ
              v0     = ( 1.0d0 - x )*v00 + x*v10
              v1     = ( 1.0d0 - x )*v01 + x*v11
              output = ( 1.0d0 - y )*v0  + y*v1 
              return 
      end select


  end subroutine pr_TrilinearDerivative



  subroutine pr_Trilinear( this, x, y, z, v000, v100, v010, v110, v001, v101, v011, v111, output )
      !-----------------------------------------------------------
      ! Compute trilinear interpolation of corner values
      ! into the given coordinates 
      !  
      ! Params
      !     - x, y, z : coordinates to interpolate
      !     - vijk    : values at corresponding corners
      !     - output  : the output variable
      !-----------------------------------------------------------
      ! Specifications
      !-----------------------------------------------------------
      implicit none
      class (TrackSubCellType) :: this
      ! input
      doubleprecision, intent(in):: x, y, z
      doubleprecision, intent(in):: v000, v100, v010, v110, v001, v101, v011, v111
      ! output
      doubleprecision, intent(inout) :: output
      ! local
      doubleprecision :: v0, v1, v00, v10, v01, v11
      !-----------------------------------------------------------
      
      ! Initialize
      output = 0d0

      v00    = ( 1.0d0 - x )*v000 + x*v100
      v01    = ( 1.0d0 - x )*v001 + x*v101
      v10    = ( 1.0d0 - x )*v010 + x*v110
      v11    = ( 1.0d0 - x )*v011 + x*v111
      v0     = ( 1.0d0 - y )*v00  + y*v10
      v1     = ( 1.0d0 - y )*v01  + y*v11
      output = ( 1.0d0 - z )*v0   + z*v1


  end subroutine pr_Trilinear


  ! RWPT
  subroutine pr_ComputeNonlinearDispersivities( this, vx, vy, vz, Daqueous, distance, &
                                                  delta, betaL, betaT, alphaL, alphaT )
      !----------------------------------------------------------------
      ! Compute nonlinear equivalent dispersivities
      ! establishing analogy with 
      ! model from  Chiogna et al. 2010, Rolle et al. 2013
      !  
      ! Params:
      !----------------------------------------------------------------
      ! Specifications
      !----------------------------------------------------------------
      implicit none
      class (TrackSubCellType)    :: this
      ! input
      doubleprecision, intent(in) :: vx, vy, vz, Daqueous
      doubleprecision, intent(in) :: distance, delta, betaL, betaT
      ! output
      doubleprecision, intent(inout) :: alphaL, alphaT
      ! local
      doubleprecision :: v, peclet, fbase
      !---------------------------------------------------------------- 
        
      v      = 0d0
      peclet = 0d0
      fbase  = 0d0  


      v      = sqrt( vx**2 + vy**2 + vz**2 )
      peclet = v*distance/Daqueous
      fbase  = peclet**2/( peclet + 2 + 4*delta**2 )

      alphaL = (distance/peclet)*( fbase )**betaL 
      alphaT = (distance/peclet)*( fbase )**betaT

      return

  end subroutine pr_ComputeNonlinearDispersivities



end module TrackSubCellModule
