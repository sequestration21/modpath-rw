module DispersionDataModule
  use PrecisionModule, only: fp 
  implicit none
  
  ! Set default access status to private
  private

  type, public :: DispersionDataType
    integer            :: id
    character(len=20)  :: stringid

    ! 1: linear isotropic ( the only available )
    ! 2: nonlinear        ( not implemented )
    integer :: modelKind = 1
    
    ! 0: uniform 
    ! 1: distributed, u3d reader
    integer :: parametersFormat 
    
    ! Identificatory flag
    logical :: uniformParameters 


    ! Ideally there is something to identify whether
    ! parameters are distributed or not 

    ! Dispersivities for linear dispersion model
    real(fp),dimension(:),allocatable :: AlphaL
    real(fp),dimension(:),allocatable :: AlphaTH ! AlphaT is pointing HERE!
    real(fp),dimension(:),allocatable :: AlphaTV
    real(fp),dimension(:),allocatable :: DMEff   ! Effective, corrected by tortuosity

    ! Parameters for nonlinear dispersion model 
    real(fp) :: dmaqueous = 0.0_fp
    real(fp),dimension(:),allocatable :: BetaL
    real(fp),dimension(:),allocatable :: BetaTH
    real(fp),dimension(:),allocatable :: BetaTV
    real(fp),dimension(:),allocatable :: Delta
    real(fp),dimension(:),allocatable :: DGrain

    logical :: initialized =.false.

  contains
    procedure :: Reset => pr_Reset
    procedure :: InitializeParameters => pr_InitializeParameters
  end type


contains


  subroutine pr_Reset( this )
    !-------------------------------------------------------------------------
    ! Specifications
    !-------------------------------------------------------------------------
    implicit none
    class(DispersionDataType) :: this
    !-------------------------------------------------------------------------

    this%initialized = .false.
    this%id          = 0
    this%stringid    = '' 
    this%dmaqueous   = 0d0
    if(allocated(this%AlphaL)) deallocate(this%AlphaL)
    if(allocated(this%AlphaTH)) deallocate(this%AlphaTH)
    if(allocated(this%AlphaTV)) deallocate(this%AlphaTV)
    if(allocated(this%DMEff)) deallocate(this%DMEff)
    if(allocated(this%BetaL)) deallocate(this%BetaL)
    if(allocated(this%BetaTH)) deallocate(this%BetaTH)
    if(allocated(this%BetaTV)) deallocate(this%BetaTV)
    if(allocated(this%Delta)) deallocate(this%Delta)
    if(allocated(this%DGrain)) deallocate(this%DGrain)

  end subroutine pr_Reset


  subroutine pr_InitializeParameters( this, cellCount ) 
    !-------------------------------------------------------------------------
    ! Specifications
    !-------------------------------------------------------------------------
    implicit none
    class(DispersionDataType) :: this
    integer :: cellCount
    !-------------------------------------------------------------------------

    select case(this%parametersFormat)
    ! spatially uniform
    case(0)
     ! Set the flag
     this%uniformParameters = .true.

     ! Linear isotropic 
     select case( this%modelKind )
       case (1)
         if(allocated(this%DMEff)) deallocate(this%DMEff)
         if(allocated(this%AlphaL)) deallocate(this%AlphaL)
         if(allocated(this%AlphaTH)) deallocate(this%AlphaTH)
         !if(allocated(this%AlphaTV)) deallocate(this%AlphaTV)
         allocate(this%DMEff(1))
         allocate(this%AlphaL(1))
         allocate(this%AlphaTH(1))
         !allocate(this%AlphaTV(cellCount))
     end select

    ! distributed
    case(1)
     ! Set the flag
     this%uniformParameters = .false.

     ! Linear isotropic 
     select case( this%modelKind )
       case (1)
         if(allocated(this%DMEff)) deallocate(this%DMEff)
         if(allocated(this%AlphaL)) deallocate(this%AlphaL)
         if(allocated(this%AlphaTH)) deallocate(this%AlphaTH)
         !if(allocated(this%AlphaTV)) deallocate(this%AlphaTV)
         allocate(this%DMEff(cellCount))
         allocate(this%AlphaL(cellCount))
         allocate(this%AlphaTH(cellCount))
         !allocate(this%AlphaTV(cellCount))
       !case (2)
       !  if(allocated(this%DMEff)) deallocate(this%DMEff)
       !  if(allocated(this%BetaL)) deallocate(this%BetaL)
       !  if(allocated(this%BetaTH)) deallocate(this%BetaTH)
       !  if(allocated(this%BetaTV)) deallocate(this%BetaTV)
       !  if(allocated(this%Delta)) deallocate(this%Delta)
       !  if(allocated(this%DGrain)) deallocate(this%DGrain)
       !  allocate(this%DMEff(cellCount))
       !  allocate(this%BetaL(cellCount))
       !  allocate(this%BetaTH(cellCount))
       !  allocate(this%BetaTV(cellCount))
       !  allocate(this%Delta(cellCount))
       !  allocate(this%DGrain(cellCount))
     end select
    end select


  end subroutine pr_InitializeParameters


end module DispersionDataModule
