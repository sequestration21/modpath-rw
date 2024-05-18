module FlowModelDataModule
  use BudgetReaderModule,only : BudgetReaderType
  use HeadReaderModule,only : HeadReaderType
  use BudgetListItemModule,only : BudgetListItemType
  use ModflowRectangularGridModule,only : ModflowRectangularGridType
  use BudgetRecordHeaderModule,only : BudgetRecordHeaderType
  use TimeDiscretizationDataModule,only : TimeDiscretizationDataType
  use UtilMiscModule,only : TrimAll
  use UTL8MODULE,only : ustop
  implicit none
  !--------------------------------------------------------------------------------------

  ! Set default access status to private
  private

    type,public :: FlowModelDataType
      logical :: Initialized = .false.
      logical :: SteadyState = .true.
      integer :: DefaultIfaceCount
      doubleprecision :: HDry = 0d0
      doubleprecision :: HNoFlow = 0d0
      character(len=16),dimension(20) :: DefaultIfaceLabels
      integer,dimension(20) :: DefaultIfaceValues
      integer,allocatable,dimension(:) :: IBoundTS
      integer,allocatable,dimension(:) :: ArrayBufferInt
      doubleprecision,allocatable,dimension(:) :: Heads
      doubleprecision,allocatable,dimension(:) :: FlowsJA
      doubleprecision,allocatable,dimension(:) :: FlowsRightFace
      doubleprecision,allocatable,dimension(:) :: FlowsFrontFace
      doubleprecision,allocatable,dimension(:) :: FlowsLowerFace
      doubleprecision,allocatable,dimension(:) :: SourceFlows
      doubleprecision,allocatable,dimension(:) :: SinkFlows
      doubleprecision,allocatable,dimension(:) :: StorageFlows
      doubleprecision,allocatable,dimension(:) :: BoundaryFlows
      doubleprecision,allocatable,dimension(:) :: SubFaceFlows
      doubleprecision,allocatable,dimension(:) :: ArrayBufferDbl

      ! Externally assigned arrays
      integer,dimension(:),pointer :: IBound
      integer,dimension(:),pointer :: Zones
      doubleprecision,dimension(:),pointer :: Porosity
      doubleprecision,dimension(:),pointer :: Retardation
     
      type(HeadReadertype)  , pointer :: HeadReader   => null()
      type(BudgetReaderType), pointer :: BudgetReader => null()
      class(ModflowRectangularGridType),pointer :: Grid => null()
      type(BudgetListItemType),allocatable,dimension(:) :: ListItemBuffer
      logical,allocatable,dimension(:), private :: SubFaceFlowsComputed
      
      ! Private variables
      integer,private :: CurrentStressPeriod = 0
      integer,private :: CurrentTimeStep = 0
    

    contains

      procedure :: Initialize=>pr_Initialize
      procedure :: Reset=>pr_Reset
      procedure :: LoadTimeStep=>pr_LoadTimeStep
      procedure :: ClearTimeStepBudgetData=>pr_ClearTimeStepBudgetData
      procedure :: GetCurrentStressPeriod=>pr_GetCurrentStressPeriod
      procedure :: GetCurrentTimeStep=>pr_GetCurrentTimeStep
      procedure :: SetIBound=>pr_SetIBound
      procedure :: SetZones=>pr_SetZones
      procedure :: SetPorosity=>pr_SetPorosity
      procedure :: SetRetardation=>pr_SetRetardation
      procedure :: SetDefaultIface=>pr_SetDefaultIface
      procedure :: CheckForDefaultIface=>pr_CheckForDefaultIface

      ! DEV
      procedure :: ValidateAuxVarNames => pr_ValidateAuxVarNames
      procedure :: LoadFlowAndAuxTimeseries => pr_LoadFlowAndAuxTimeseries
      procedure :: ValidateBudgetHeader => pr_ValidateBudgetHeader
      procedure :: LoadFlowTimeseries => pr_LoadFlowTimeseries

    end type


contains


    subroutine pr_Initialize(this,headReader, budgetReader, grid, hNoFlow, hDry)
    !---------------------------------------------------------------------------
    !
    !---------------------------------------------------------------------------
    ! Specifications
    !---------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    type(BudgetReaderType),intent(inout),target :: budgetReader
    type(HeadReaderType),intent(inout),target :: headReader
    class(ModflowRectangularGridType),intent(inout),pointer :: grid
    integer :: cellCount,gridType
    integer :: flowArraySize
    doubleprecision :: hNoFlow, hDry
    !---------------------------------------------------------------------------

      this%Initialized = .false.
      
      ! Call Reset to make sure that all arrays are initially unallocated
      call this%Reset()
      
      ! Return if the grid cell count equals 0
      cellCount = grid%CellCount
      if(cellCount .le. 0) return
      
      ! Check budget reader and grid data for compatibility and allocate appropriate cell-by-cell flow arrays
      gridType = grid%GridType
      select case (gridType)
        case (1)
          if((budgetReader%GetBudgetType() .ne. 1)) return
          if((headReader%GridStyle .ne. 1) .or. (headReader%CellCount .ne. cellCount)) return
          flowArraySize = budgetReader%GetFlowArraySize()
          if(flowArraySize .ne. cellCount) return
          allocate(this%FlowsRightFace(flowArraySize))
          allocate(this%FlowsFrontFace(flowArraySize))
          allocate(this%FlowsLowerFace(flowArraySize))
          allocate(this%FlowsJA(0))
        case (2)
          if((budgetReader%GetBudgetType() .ne. 2)) return
          if((headReader%GridStyle .ne. 2) .or. (headReader%CellCount .ne. cellCount)) return
          flowArraySize = budgetReader%GetFlowArraySize()
          if(flowArraySize .ne. grid%JaCount) return
          allocate(this%FlowsJA(flowArraySize))
          allocate(this%FlowsRightFace(0))
          allocate(this%FlowsFrontFace(0))
          allocate(this%FlowsLowerFace(0))
        case (3, 4)
          ! RWPT: In case budget and/or head were not saved 
          ! for all times, there is an error triggered 
          ! downstream because of the early exits at this point.
          ! Specifically, the headReader%CellCount is not properly defined.
          if((budgetReader%GetBudgetType() .ne. 2)) return
          if((headReader%GridStyle .ne. 1) .or. (headReader%CellCount .ne. cellCount)) return
          flowArraySize = budgetReader%GetFlowArraySize()
          if(flowArraySize .ne. grid%JaCount) return
          allocate(this%FlowsJA(flowArraySize))
          allocate(this%FlowsRightFace(0))
          allocate(this%FlowsFrontFace(0))
          allocate(this%FlowsLowerFace(0))          
        !case (4)
        !    ! Not implemented
        !    return
        case default
            return
      end select
      
      ! Set pointers to budgetReader and grid. Assign tracking options.
      this%HeadReader => headReader
      this%BudgetReader => budgetReader
      this%Grid => grid
      this%HNoFlow = hNoFlow
      this%HDry = hDry
      
      ! Allocate the rest of the arrays
      allocate(this%IBoundTS(cellCount))
      allocate(this%Heads(cellCount))
      allocate(this%SourceFlows(cellCount))
      allocate(this%SinkFlows(cellCount))
      allocate(this%StorageFlows(cellCount))
      allocate(this%SubFaceFlowsComputed(cellCount))
      allocate(this%BoundaryFlows(cellCount * 6))
      allocate(this%SubFaceFlows(cellCount * 4))
      
      ! Allocate buffers for reading array and list data
      allocate(this%ListItemBuffer(this%BudgetReader%GetMaximumListItemCount()))
      allocate(this%ArrayBufferDbl(this%BudgetReader%GetMaximumArrayItemCount()))  
      allocate(this%ArrayBufferInt(this%BudgetReader%GetMaximumArrayItemCount()))
      
      this%Initialized = .true.
  

    end subroutine pr_Initialize


    subroutine pr_Reset(this)
    !---------------------------------------------------------------------------
    !
    !---------------------------------------------------------------------------
    ! Specifications
    !---------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    !---------------------------------------------------------------------------
       
      !this%ReferenceTime = 0.0d0
      !this%StoppingTime = 0.0d0
      this%CurrentStressPeriod = 0
      this%CurrentTimeStep = 0
      this%HeadReader => null()
      this%BudgetReader => null()
      this%Grid => null()
      
      if(allocated(this%IBoundTS)) deallocate(this%IBoundTS)
      if(allocated(this%ArrayBufferInt)) deallocate(this%ArrayBufferInt)
      if(allocated(this%Heads)) deallocate(this%Heads)
      if(allocated(this%FlowsJA)) deallocate(this%FlowsJA)
      if(allocated(this%FlowsRightFace)) deallocate(this%FlowsRightFace)
      if(allocated(this%FlowsFrontFace)) deallocate(this%FlowsFrontFace)
      if(allocated(this%FlowsLowerFace)) deallocate(this%FlowsLowerFace)
      if(allocated(this%SourceFlows)) deallocate(this%SourceFlows)
      if(allocated(this%SinkFlows)) deallocate(this%SinkFlows)
      if(allocated(this%StorageFlows)) deallocate(this%StorageFlows)
      if(allocated(this%BoundaryFlows)) deallocate(this%BoundaryFlows)
      if(allocated(this%SubFaceFlows)) deallocate(this%SubFaceFlows)
      if(allocated(this%ArrayBufferDbl)) deallocate(this%ArrayBufferDbl)
      if(allocated(this%ListItemBuffer)) deallocate(this%ListItemBuffer)
      if(allocated(this%SubFaceFlowsComputed)) deallocate(this%SubFaceFlowsComputed)
      this%IBound => null()
      this%Porosity => null()
      this%Retardation => null()
      this%Zones => null()

    end subroutine pr_Reset


    subroutine pr_LoadTimeStep(this, stressPeriod, timeStep)
    !------------------------------------------------------------------------
    !
    !------------------------------------------------------------------------
    ! Specifications
    !------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    integer,intent(in) :: stressPeriod, timeStep
    integer :: firstRecord, lastRecord, n, m, firstNonBlank, lastNonBlank, &
      trimmedLength
    integer :: spaceAssigned, status,cellCount, iface, index,              &
      boundaryFlowsOffset, listItemBufferSize, cellNumber, layer
    type(BudgetRecordHeaderType) :: header
    character(len=16) :: textLabel
    character(len=132) message
    real :: HDryTol, HDryDiff
    !------------------------------------------------------------------------
      
      call this%ClearTimeStepBudgetData()
      call this%BudgetReader%GetRecordHeaderRange(stressPeriod, timeStep, firstRecord, lastRecord)
      if(firstRecord .eq. 0) then
        write(message,'(A,I5,A,I5,A)') ' Error loading Time Step ', timeStep, ' Period ', stressPeriod, '.'
        message = trim(message)
        write(*,'(A)') message
        call ustop('Missing budget information. Budget file must have output for every time step. Stop.')
      end if

      cellCount = this%Grid%CellCount
      listItemBufferSize = size(this%ListItemBuffer)
      
      ! Set steady state = true, then change it if the budget file contains storage
      this%SteadyState = .true.
      
      ! Load heads for this time step
      call this%HeadReader%FillTimeStepHeadBuffer(stressPeriod, timeStep, &
        this%Heads, cellCount, spaceAssigned)
      
      ! Fill IBoundTS array and set the SaturatedTop array for the Grid.
      ! The saturated top is set equal to the top for confined cells and water table cells 
      ! where the head is above the top or below the bottom.
      HDryTol = abs(epsilon(HDryTol)*sngl(this%HDry))
      if(this%Grid%GridType .gt. 2) then ! MODFLOW-6 DIS, DISV
        do n = 1, cellCount
          this%Grid%SaturatedTop(n) = this%Grid%Top(n)
          this%StorageFlows(n) = 0.0
          this%IBoundTS(n) = this%IBound(n)
          layer = this%Grid%GetLayer(n)
          if(this%Grid%CellType(n) .eq. 1) then
            HDryDiff = sngl(this%Heads(n)) - sngl(this%HDry)
            if(abs(HDryDiff) .lt. HDryTol) then
              this%IBoundTS(n) = 0
              if(this%Heads(n) .lt. this%Grid%Bottom(n)) then
                this%IBoundTS(n) = 0
                this%Grid%SaturatedTop(n) = this%Grid%Bottom(n)
              end if
            end if
            if(this%IBoundTS(n) .ne. 0) then
              if((this%Heads(n) .le. this%Grid%Top(n)) .and. &
                (this%Heads(n) .ge. this%Grid%Bottom(n))) then
                  this%Grid%SaturatedTop(n) = this%Heads(n)
              end if
            end if
          end if
        end do
      else
        do n = 1, cellCount
          this%Grid%SaturatedTop(n) = this%Grid%Top(n)
          this%StorageFlows(n) = 0.0
          this%IBoundTS(n) = this%IBound(n)
          layer = this%Grid%GetLayer(n)
          if(this%Grid%CellType(n) .eq. 1) then
            HDryDiff = sngl(this%Heads(n)) - sngl(this%HDry)
            if((abs(HDryDiff) .lt. HDryTol) .or. (this%Heads(n) .gt. 1.0d+6)) then
              this%IBoundTS(n) = 0
            end if
            if(this%IBoundTS(n) .ne. 0) then
              if((this%Heads(n) .le. this%Grid%Top(n)) .and. &
                (this%Heads(n) .ge. this%Grid%Bottom(n))) then
                  this%Grid%SaturatedTop(n) = this%Heads(n)
              end if
            end if
          end if
        end do
      end if

      ! Loop through record headers
      do n = firstRecord, lastRecord
        header = this%BudgetReader%GetRecordHeader(n)
        textLabel = header%TextLabel
        call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
        select case(textLabel(firstNonBlank:lastNonBlank))
        case('CONSTANT HEAD', 'CHD')
          ! Read constant head flows into the sinkFlows and sourceFlows arrays.
          ! For a standard budget file, Method = 0. For a compact budget file,
          ! Method = 2.
          if(header%Method .eq. 0) then
            call this%BudgetReader%FillRecordDataBuffer(header,       &
              this%ArrayBufferDbl, cellCount, spaceAssigned, status)
            if(cellCount .eq. spaceAssigned) then
              do m = 1, spaceAssigned
                if(this%ArrayBufferDbl(m) .gt. 0.0d0) then
                  this%SourceFlows(m) = this%SourceFlows(m) +         &
                    this%ArrayBufferDbl(m)
                else if(this%ArrayBufferDbl(m) .lt. 0.0d0) then
                  this%SinkFlows(m) = this%SinkFlows(m) +             &
                    this%ArrayBufferDbl(m)
                end if
              end do
            end if
          else if(header%Method .eq. 2) then
            call this%BudgetReader%FillRecordDataBuffer(header,             &
              this%ListItemBuffer, listItemBufferSize, spaceAssigned, status)
            if(spaceAssigned .gt. 0) then
              do m = 1, spaceAssigned
                cellNumber = this%ListItemBuffer(m)%CellNumber
                if(this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                  this%SourceFlows(cellNumber) =                      &
                    this%SourceFlows(cellNumber) + this%ListItemBuffer(m)%BudgetValue
                else if(this%ListItemBuffer(m)%BudgetValue .lt. 0.0d0) then
                  this%SinkFlows(cellNumber) =                        &
                    this%SinkFlows(cellNumber) + this%ListItemBuffer(m)%BudgetValue
                end if
              end do
            end if
          else if((header%Method .eq. 5) .or. (header%Method .eq. 6)) then
            call this%BudgetReader%FillRecordDataBuffer(header,             &
              this%ListItemBuffer, listItemBufferSize, spaceAssigned,       &
              status)
            if(spaceAssigned .gt. 0) then
              do m = 1, spaceAssigned
                call this%CheckForDefaultIface(header%TextLabel, iface)
                index = header%FindAuxiliaryNameIndex('IFACE')
                if(index .gt. 0) then
                  iface = int(this%ListItemBuffer(m)%AuxiliaryValues(index))
                end if
                
                cellNumber = this%ListItemBuffer(m)%CellNumber
                if(iface .gt. 0) then
                  boundaryFlowsOffset = 6 * (cellNumber - 1)
                  this%BoundaryFlows(boundaryFlowsOffset + iface) =   &
                    this%BoundaryFlows(boundaryFlowsOffset + iface) + &
                    this%ListItemBuffer(m)%BudgetValue
                else
                  if(this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                    this%SourceFlows(cellNumber) =                  &
                      this%SourceFlows(cellNumber) +                &
                      this%ListItemBuffer(m)%BudgetValue
                  else if(this%ListItemBuffer(m)%BudgetValue .lt. 0.0d0) then
                    this%SinkFlows(cellNumber) =                    &
                      this%SinkFlows(cellNumber) +                  &
                      this%ListItemBuffer(m)%BudgetValue
                  end if
                end if
              end do
            end if
          end if
          
        case('STORAGE', 'STO-SS', 'STO-SY')
          ! Read storage for all cells into the StorageFlows array.
          ! Method should always be 0 or 1, but check anyway to be sure.
          if((header%Method .eq. 0) .or. (header%Method .eq. 1)) then
            if(header%ArrayItemCount .eq. cellCount) then
              call this%BudgetReader%FillRecordDataBuffer(header,         &
                this%ArrayBufferDbl, cellCount, spaceAssigned, status)
              if(cellCount .eq. spaceAssigned) then
                do m = 1, spaceAssigned
                  this%StorageFlows(m) = this%StorageFlows(m) + this%ArrayBufferDbl(m)
                  if(this%StorageFlows(m) .ne. 0.0) this%SteadyState = .false.
                end do
              end if
            end if
          end if
            
        case('FLOW JA FACE', 'FLOW-JA-FACE')
          ! Read connected face flows into the FlowsJA array for unstructured grids.
          if((header%Method .eq. 0) .or. (header%Method .eq. 1)) then
            ! Method should always be 0 or 1 for flow between grid cells. 
            if(header%ArrayItemCount .eq. this%BudgetReader%GetFlowArraySize()) then
              call this%BudgetReader%FillRecordDataBuffer(header,         &
                this%FlowsJA, header%ArrayItemCount, spaceAssigned,       &
                status)
            end if
          else if(header%Method .eq. 6) then
            ! Method code 6 indicates flow to or from cells in the current model grid
            ! and another connected model grid in a multi-model MODFLOW-6 simulation. 
            ! Treat flows to or from connected model grids as distributed source/sink flows 
            ! for the current grid.
            call this%BudgetReader%FillRecordDataBuffer(header,       &
              this%ListItemBuffer, listItemBufferSize, spaceAssigned, &
              status)
            if(spaceAssigned .gt. 0) then
              do m = 1, spaceAssigned
                cellNumber = this%ListItemBuffer(m)%CellNumber
                if(this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                  this%SourceFlows(cellNumber) =                  &
                      this%SourceFlows(cellNumber) +              &
                      this%ListItemBuffer(m)%BudgetValue
                else if(this%ListItemBuffer(m)%BudgetValue .lt. 0.0d0) then
                  this%SinkFlows(cellNumber) =                    &
                      this%SinkFlows(cellNumber) +                &
                      this%ListItemBuffer(m)%BudgetValue
                end if
              end do
            end if
          end if
            
        case('FLOW RIGHT FACE')
          ! Read flows across the right face for structured grids.
          ! Method should always be 0 or 1, but check anyway to be sure.
          if((header%Method .eq. 0) .or. (header%Method .eq. 1)) then
            if(header%ArrayItemCount .eq. this%BudgetReader%GetFlowArraySize()) then
              call this%BudgetReader%FillRecordDataBuffer(header,         &
                this%FlowsRightFace, header%ArrayItemCount, spaceAssigned,&
                status)
            end if
          end if
            
        case('FLOW FRONT FACE')
          ! Read flows across the front face for structured grids.
          ! Method should always be 0 or 1, but check anyway to be sure.
          if((header%Method .eq. 0) .or. (header%Method .eq. 1)) then
            if(header%ArrayItemCount .eq. this%BudgetReader%GetFlowArraySize()) then
              call this%BudgetReader%FillRecordDataBuffer(header,         &
                this%FlowsFrontFace, header%ArrayItemCount, spaceAssigned,&
                status)
            end if
          end if
            
        case('FLOW LOWER FACE')
          ! Read flows across the lower face for structured grids.
          ! Method should always be 0 or 1, but check anyway to be sure.
          if((header%Method .eq. 0) .or. (header%Method .eq. 1)) then
            if(header%ArrayItemCount .eq. this%BudgetReader%GetFlowArraySize()) then
              call this%BudgetReader%FillRecordDataBuffer(header,         &
                this%FlowsLowerFace, header%ArrayItemCount, spaceAssigned,&
                status)
            end if
          end if

        case('DATA-SPDIS', 'DATA-SAT')
          ! Skip
          ! The “DATA” prefix on the text identifier can
          ! be used by post-processors to recognize that the record
          ! does not contain a cell flow budget term.
          cycle
          
        case default
          ! Now handle any other records in the budget file.
          if((header%Method .eq. 0) .or. (header%Method .eq. 1)) then
            if(header%ArrayItemCount .eq. cellCount) then
              call this%BudgetReader%FillRecordDataBuffer(header,         &
                this%ArrayBufferDbl, cellCount, spaceAssigned, status)
              if(cellCount .eq. spaceAssigned) then
                call this%CheckForDefaultIface(header%TextLabel, iface)
                if(iface .gt. 0) then
                  do m = 1, spaceAssigned
                    boundaryFlowsOffset = 6 * (m - 1)
                    this%BoundaryFlows(boundaryFlowsOffset + iface) =   &
                      this%BoundaryFlows(boundaryFlowsOffset + iface) + &
                      this%ArrayBufferDbl(m)
                  end do
                else
                  do m = 1, spaceAssigned
                    if(this%ArrayBufferDbl(m) .gt. 0.0d0) then
                      this%SourceFlows(m) = this%SourceFlows(m) +     &
                        this%ArrayBufferDbl(m)
                    else if(this%ArrayBufferDbl(m) .lt. 0.0d0) then
                      this%SinkFlows(m) = this%SinkFlows(m) +         &
                        this%ArrayBufferDbl(m)
                    end if
                  end do
                end if
              end if
            end if
          else if(header%Method .eq. 3) then
            call this%BudgetReader%FillRecordDataBuffer(header,             &
              this%ArrayBufferDbl, this%ArrayBufferInt,                     &
              header%ArrayItemCount, spaceAssigned, status)
            if(header%ArrayItemCount .eq. spaceAssigned) then
              call this%CheckForDefaultIface(header%TextLabel, iface)
              if(iface .gt. 0) then
                do m = 1, spaceAssigned
                  if(this%Grid%GridType .ne. 2) then
                    ! structured
                    layer = this%ArrayBufferInt(m)
                    cellNumber = (layer - 1) * spaceAssigned + m
                  else
                    ! mfusg unstructured
                    cellNumber = this%ArrayBufferInt(m)
                  end if
                  boundaryFlowsOffset = 6 * (cellNumber - 1)
                  this%BoundaryFlows(boundaryFlowsOffset + iface) =   &
                    this%BoundaryFlows(boundaryFlowsOffset + iface) + &
                    this%ArrayBufferDbl(m)
                end do
              else            
                do m = 1, spaceAssigned
                  cellNumber = this%ArrayBufferInt(m)
                  if(this%ArrayBufferDbl(m) .gt. 0.0d0) then
                    this%SourceFlows(cellNumber) =                  &
                      this%SourceFlows(cellNumber) +                &
                      this%ArrayBufferDbl(m)
                  else if(this%ArrayBufferDbl(m) .lt. 0.0d0) then
                    this%SinkFlows(cellNumber) =                    &
                      this%SinkFlows(cellNumber) +                  &
                      this%ArrayBufferDbl(m)
                  end if
                end do
              end if
            end if
          else if(header%Method .eq. 4) then
            call this%BudgetReader%FillRecordDataBuffer(header,             &
              this%ArrayBufferDbl, header%ArrayItemCount, spaceAssigned,    &
              status)
            if(header%ArrayItemCount .eq. spaceAssigned) then
              call this%CheckForDefaultIface(header%TextLabel, iface)
              if(iface .gt. 0) then
                do m = 1, spaceAssigned
                  boundaryFlowsOffset = 6 * (m - 1)
                  this%BoundaryFlows(boundaryFlowsOffset + iface) =   &
                    this%BoundaryFlows(boundaryFlowsOffset + iface) + &
                    this%ArrayBufferDbl(m)
                end do
              else            
                do m = 1, spaceAssigned
                  if(this%ArrayBufferDbl(m) .gt. 0.0d0) then
                    this%SourceFlows(m) = this%SourceFlows(m) +     &
                      this%ArrayBufferDbl(m)
                  else if(this%ArrayBufferDbl(m) .lt. 0.0d0) then
                    this%SinkFlows(m) = this%SinkFlows(m) +         &
                      this%ArrayBufferDbl(m)
                  end if
                end do
              end if
            end if
          else if(header%Method .eq. 2) then
            call this%BudgetReader%FillRecordDataBuffer(header,             &
              this%ListItemBuffer, listItemBufferSize, spaceAssigned,       &
              status)
            if(spaceAssigned .gt. 0) then
              call this%CheckForDefaultIface(header%TextLabel, iface)
              if(iface .gt. 0) then
                do m = 1, spaceAssigned
                    cellNumber = this%ListItemBuffer(m)%CellNumber
                    boundaryFlowsOffset = 6 * (cellNumber - 1)
                    this%BoundaryFlows(boundaryFlowsOffset + iface) =   &
                      this%BoundaryFlows(boundaryFlowsOffset + iface) + &
                      this%ListItemBuffer(m)%BudgetValue
                end do
              else            
                do m = 1, spaceAssigned
                  cellNumber = this%ListItemBuffer(m)%CellNumber
                  if(this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                    this%SourceFlows(cellNumber) =                  &
                      this%SourceFlows(cellNumber) +                &
                      this%ListItemBuffer(m)%BudgetValue
                  else if(this%ListItemBuffer(m)%BudgetValue .lt. 0.0d0) then
                    this%SinkFlows(cellNumber) =                    &
                      this%SinkFlows(cellNumber) +                  &
                      this%ListItemBuffer(m)%BudgetValue
                  end if
                end do
              end if
            end if
          else if((header%Method .eq. 5) .or. (header%Method .eq. 6)) then
            call this%BudgetReader%FillRecordDataBuffer(header,             &
              this%ListItemBuffer, listItemBufferSize, spaceAssigned,       &
              status)
            if(spaceAssigned .gt. 0) then
              do m = 1, spaceAssigned
                call this%CheckForDefaultIface(header%TextLabel, iface)
                index = header%FindAuxiliaryNameIndex('IFACE')
                if(index .gt. 0) then
                  iface = int(this%ListItemBuffer(m)%AuxiliaryValues(index))
                end if
                cellNumber = this%ListItemBuffer(m)%CellNumber
                if(iface .gt. 0) then
                  boundaryFlowsOffset = 6 * (cellNumber - 1)
                  this%BoundaryFlows(boundaryFlowsOffset + iface) =   &
                    this%BoundaryFlows(boundaryFlowsOffset + iface) + &
                    this%ListItemBuffer(m)%BudgetValue
                else
                  if(this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                    this%SourceFlows(cellNumber) =                  &
                      this%SourceFlows(cellNumber) +                &
                      this%ListItemBuffer(m)%BudgetValue
                  else if(this%ListItemBuffer(m)%BudgetValue .lt. 0.0d0) then
                    this%SinkFlows(cellNumber) =                    &
                      this%SinkFlows(cellNumber) +                  &
                      this%ListItemBuffer(m)%BudgetValue
                  end if
                end if
              end do
            end if
          end if
        
        end select
        
      end do
    
      this%CurrentStressPeriod = stressPeriod
      this%CurrentTimeStep = timeStep
   

    end subroutine pr_LoadTimeStep


    subroutine pr_ClearTimeStepBudgetData(this)
    !***************************************************************************************************************
    !
    !***************************************************************************************************************
    !
    ! Specifications
    !---------------------------------------------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    integer :: cellCount, n, arraySize
    !---------------------------------------------------------------------------------------------------------------
      
      this%CurrentStressPeriod = 0
      this%CurrentTimeStep = 0
      
      if(allocated(this%SinkFlows)) then
        cellCount = this%Grid%CellCount
        do n = 1, cellCount
          this%IBoundTS(n) = this%IBound(n)
          this%Heads(n) = 0.0d0
          this%SourceFlows(n) = 0.0d0
          this%SinkFlows(n) = 0.0d0
          this%StorageFlows(n) = 0.0d0
          this%SubFaceFlowsComputed(n) = .false.
        end do
        
        arraySize = cellCount * 6
        do n = 1, arraySize
          this%BoundaryFlows(n) = 0.0d0
        end do
        
        arraySize = cellCount * 4
        do n = 1, arraySize
          this%SubFaceFlows(n) = 0.0d0
        end do
      
        arraySize = this%BudgetReader%GetFlowArraySize()
        if(this%Grid%GridType .eq. 1) then
          do n = 1, arraySize
            this%FlowsRightFace(n) = 0.0d0
            this%FlowsFrontFace(n) = 0.0d0
            this%FlowsLowerFace(n) = 0.0d0
          end do
        else if(this%Grid%GridType .eq. 2) then
          do n = 1, arraySize
            this%FlowsJA(n) = 0.0d0
          end do
        end if
      end if


    end subroutine pr_ClearTimeStepBudgetData


    function pr_GetCurrentStressPeriod(this) result(stressPeriod)
    !***************************************************************************************************************
    !
    !***************************************************************************************************************
    ! Specifications
    !---------------------------------------------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    integer :: stressPeriod
    !---------------------------------------------------------------------------------------------------------------
     

        stressPeriod = this%CurrentStressPeriod
     

    end function pr_GetCurrentStressPeriod


    function pr_GetCurrentTimeStep(this) result(timeStep)
    !***************************************************************************************************************
    !
    !***************************************************************************************************************
    ! Specifications
    !---------------------------------------------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    integer :: timeStep
    !---------------------------------------------------------------------------------------------------------------
    

        timeStep = this%CurrentTimeStep
      

    end function pr_GetCurrentTimeStep


    subroutine pr_SetIBound(this, ibound, arraySize)
    !***************************************************************************************************************
    !
    !***************************************************************************************************************
    ! Specifications
    !---------------------------------------------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    integer,intent(in) :: arraySize
    integer :: n
    integer,dimension(arraySize),intent(in),target :: ibound
    !---------------------------------------------------------------------------------------------------------------
     
      if(arraySize .ne. this%Grid%CellCount) then
        write(*,*) "FlowModelDataType: The IBound array size does not match the cell count for the grid. stop"
        stop
      end if
      
      this%IBound => ibound
      ! Initialize the IBoundTS array to the same values as IBound whenever the IBound array is set.
      ! The values of IBoundTS will be updated for dry cells every time that data for a time step is loaded.
      do n = 1, arraySize
        this%IBoundTS(n) = this%IBound(n)
      end do

    end subroutine pr_SetIBound


    subroutine pr_SetZones(this, zones, arraySize)
    !***************************************************************************************************************
    !
    !***************************************************************************************************************
    ! Specifications
    !---------------------------------------------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    integer,intent(in) :: arraySize
    integer,dimension(arraySize),intent(in),target :: zones
    !---------------------------------------------------------------------------------------------------------------
      

        if(arraySize .ne. this%Grid%CellCount) then
            write(*,*) "FlowModelDataType: The Zones array size does not match the cell count for the grid. stop"
            stop
        end if
        
        this%Zones => zones
    

    end subroutine pr_SetZones


    subroutine pr_SetPorosity(this, porosity, arraySize)
    !***************************************************************************************************************
    !
    !***************************************************************************************************************
    ! Specifications
    !---------------------------------------------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    integer,intent(in) :: arraySize
    doubleprecision,dimension(arraySize),intent(in),target :: porosity
    !---------------------------------------------------------------------------------------------------------------


        if(arraySize .ne. this%Grid%CellCount) then
            write(*,*) "FlowModelDataType: The Porosity array size does not match the cell count for the grid. stop"
            stop
        end if
        
        this%Porosity => porosity


    end subroutine pr_SetPorosity


    subroutine pr_SetRetardation(this, retardation, arraySize)
    !***************************************************************************************************************
    !
    !***************************************************************************************************************
    ! Specifications
    !---------------------------------------------------------------------------------------------------------------
    implicit none
    class(FlowModelDataType) :: this
    integer,intent(in) :: arraySize
    doubleprecision,dimension(arraySize),intent(in),target :: retardation
    !---------------------------------------------------------------------------------------------------------------
  

        if(arraySize .ne. this%Grid%CellCount) then
            write(*,*) "FlowModelDataType: The Retardation array size does not match the cell count for the grid. stop"
            stop
        end if
        
        this%Retardation => retardation
 

    end subroutine pr_SetRetardation

  
    subroutine pr_SetDefaultIface(this, defaultIfaceLabels, defaultIfaceValues, arraySize)
    !***************************************************************************************************************
    ! Description goes here
    !***************************************************************************************************************
    ! Specifications
    !---------------------------------------------------------------------------------------------------------------
    use UtilMiscModule,only : utrimall
    implicit none
    class(FlowModelDataType) :: this
    integer,intent(in) :: arraySize
    integer,dimension(arraySize),intent(in) :: defaultIfaceValues
    character(len=16),dimension(arraySize),intent(in) :: defaultIfaceLabels
    integer :: n
    character(len=16) :: label
    !---------------------------------------------------------------------------------------------------------------
      

        this%DefaultIfaceCount = 0
        do n = 1, 20
            this%DefaultIfaceValues(n) = 0
            this%DefaultIfaceLabels(n) = '                '
        end do
        
        do n = 1, arraySize
            this%DefaultIfaceValues(n) = defaultIfaceValues(n)
            label = defaultIfaceLabels(n)
            call utrimall(label)
            this%DefaultIfaceLabels(n) = label
        end do
        this%DefaultIfaceCount = arraySize
   

    end subroutine pr_SetDefaultIface


    subroutine pr_CheckForDefaultIface(this, textLabel, iface)
    !***************************************************************************************************************
    !
    !***************************************************************************************************************
    !
    ! Specifications
    !---------------------------------------------------------------------------------------------------------------
    use UtilMiscModule,only : utrimall
    implicit none
    class(FlowModelDataType) :: this
    character*(*), intent(in) :: textLabel
    integer,intent(inout) :: iface
    integer :: n
    character(len=16) :: label
    !---------------------------------------------------------------------------------------------------------------
      
        iface = 0
        label = textLabel
        call utrimall(label)
        do n = 1, this%DefaultIfaceCount
            if(label .eq. this%DefaultIfaceLabels(n)) then
                iface = this%DefaultIfaceValues(n)
                return
            end if
        end do
      
    end subroutine pr_CheckForDefaultIface


    subroutine pr_LoadFlowAndAuxTimeseries(this, sourcePkgName, auxVarNames,& 
                                    isMF6, initialTime, finalTime, tdisData,&
                        flowTimeseries, auxTimeseries, timeIntervals, times,&
                              cellNumbers, outUnit, iFaceOption, iFaceCells,&
                                                           backwardTracking )
    !------------------------------------------------------------------------
    ! Given a range of times, extract timeseries for flow and auxvars related 
    ! to package name/budget header.
    ! 
    ! It can receive iFaceOption to extract the IFACE variable for each cell
    ! related to the source budget. The current extraction of IFACE considers 
    ! that is not changing in time.   
    !
    ! Flow rate and aux variable is extracted only for positive sign, source. 
    ! The backward tracking flag modifies the sign of the flow rate in order 
    ! to allow reversal of the boundary condition.
    !  
    !------------------------------------------------------------------------
    ! Specifications
    !------------------------------------------------------------------------
    implicit none
    ! input
    class(FlowModelDataType) :: this
    character(len=16), intent(in) :: sourcePkgName
    character(len=20), dimension(:), intent(in) :: auxVarNames
    logical, intent(in) :: isMF6
    doubleprecision, intent(in) :: initialTime, finalTime
    class( TimeDiscretizationDataType ), intent(in) :: tdisData
    integer, optional, intent(in) :: outUnit
    logical, optional, intent(in) :: iFaceOption
    ! out
    doubleprecision, allocatable, dimension(:,:)  , intent(inout) :: flowTimeseries ! nt x ncells
    doubleprecision, allocatable, dimension(:,:,:), intent(inout) :: auxTimeseries  ! nt x ncells x nauxvars
    doubleprecision, allocatable, dimension(:)    , intent(inout) :: timeIntervals  ! nt
    doubleprecision, allocatable, dimension(:)    , intent(inout) :: times          ! nt + 1
    integer        , allocatable, dimension(:)    , intent(inout) :: cellNumbers    ! nCells
    integer, allocatable, dimension(:), optional  , intent(inout) :: iFaceCells     ! nCells
    logical, optional, intent(in)                                 :: backwardTracking
    ! local
    logical :: lookForIFace = .false.
    integer :: ifaceindex
    integer :: n, m, naux
    integer :: stressPeriod, timeStep
    integer :: firstRecord,lastRecord
    integer :: firstNonBlank,lastNonBlank,trimmedLength
    integer :: firstNonBlankIn,lastNonBlankIn,trimmedLengthIn
    integer :: firstNonBlankLoc,lastNonBlankLoc,trimmedLengthLoc
    integer :: spaceAssigned, status, auxindex, cellindex
    integer :: listItemBufferSize, cellNumber
    type(BudgetRecordHeaderType) :: header
    character(len=16)  :: textLabel
    character(len=16)  :: textNameLabel
    character(len=132) :: message
    integer :: nCells, newcounter
    integer :: kinitial, kfinal, ktime, kcounter, kdelta
    integer :: nTimes, nTimeIntervals, nAuxVars
    integer :: spInit, tsInit, spEnd, tsEnd, nStressPeriods, nsp 
    integer, allocatable, dimension(:) :: tempCellNumbers
    integer, allocatable, dimension(:) :: spCellNumbers
    integer, allocatable, dimension(:) :: tempSPIFaces
    integer, allocatable, dimension(:) :: spIFaces
    doubleprecision :: sign
    logical         :: backTracking = .false.
    integer         :: correctInterval
    ! For identifying pkgs with aux vars from modflow != mf6
    logical :: foundTheSource = .false.
    integer :: nb, nbindex
    integer :: nbmax = 5
    character(len=16)  :: anamebud(5)
    DATA anamebud(1) /'           WELLS'/ ! WEL
    DATA anamebud(2) /'    DRAINS (DRT)'/ ! DRT
    DATA anamebud(3) /'          DRAINS'/ ! DRN
    DATA anamebud(4) /'   RIVER LEAKAGE'/ ! RIV
    DATA anamebud(5) /' HEAD DEP BOUNDS'/ ! GHB
    character(len=16)  :: anameid(5)
    DATA anameid(1)  /'             WEL'/ ! WEL
    DATA anameid(2)  /'             DRT'/ ! DRT
    DATA anameid(3)  /'             DRN'/ ! DRN
    DATA anameid(4)  /'             RIV'/ ! RIV
    DATA anameid(5)  /'             GHB'/ ! GHB
    !------------------------------------------------------------------------

      ! Supposedly, previous to run this function 
      ! aux variables were already validated with 
      ! call this%ValidateAuxVarNames

      ! Check the iface flag
      if ( present( iFaceOption) ) then 
        lookForIface = .false.
        ifaceindex   = 0
        lookForIFace = iFaceOption
      end if

      ! Initialize cellNumbers by deallocating if allocated
      if ( allocated( cellNumbers ) ) deallocate( cellNumbers )

      ! Initialize iFaceCells by deallocating if allocated 
      if ( present( iFaceCells ) ) then 
        if ( allocated( iFaceCells ) ) deallocate( iFaceCells ) 
      end if  

      ! Trim input pkg name
      call TrimAll(sourcePkgName, firstNonBlankIn, lastNonBlankIn, trimmedLengthIn)
      listItemBufferSize = size(this%ListItemBuffer)

      ! Determine the sign to consider for the source, for 
      ! compatibility with backward tracking.
      sign   = 1d0
      kdelta = 1
      correctInterval = 1
      backTracking = .false.
      if ( present( backwardTracking ) ) then
        if ( backwardTracking ) backTracking = .true. 
      end if 

      ! Given initial and final times, 
      ! compute the initial and final time step indexes
      ! Note 1: TotalTimes starts from dt, not zero.
      ! Note 2: FindContainingTimeStep returns the index 
      ! corresponding to the upper limit of the time interval 
      ! in TotalTimes. Meaning, if on a TotalTimes vector 
      ! [dt,2dt,...] the time 1.5dt is requested, then 
      ! the function will return the index 2, corresponding to 
      ! TotalTimes=2dt. 
      kinitial = tdisData%FindContainingTimeStep(initialTime)
      kfinal   = tdisData%FindContainingTimeStep(finalTime)
      ! There are cases in which, depending on the stoptimeoption, 
      ! finalTime may have the value 1.0d+30. Something really 
      ! big to track particles until all of them get to a stop
      ! condition for steady state models. For such value, 
      ! FindContainingTimeStep will return 0, assuming that this large
      ! number is higher than the length of the modflow simulation stoptime.
      ! In such case, it is enforced that kfinal adopt the value of 
      ! tdisData%CumulativeTimeStepCount, the highest possible value.
      if ( backTracking ) then 
        if ( (kfinal .eq. 0) ) then
         if ( present(outUnit) ) then       
          write(outUnit,'(a)') 'FlowModelData: LoadFlowAndAuxTimeseries: kfinal is assumed to be 1.'
          write(outUnit,'(a,e15.7)') 'FlowModelData: LoadFlowAndAuxTimeseries: final time is ', finalTime
         end if
         kfinal = 1
        end if
      else
        if ( (kfinal .eq. 0) ) then
         if ( present(outUnit) ) then       
          write(outUnit,'(a)')& 
           'FlowModelData: LoadFlowAndAuxTimeseries: kfinal is assumed to be CumulativeTimeStepCount'
          write(outUnit,'(a,e15.7)')& 
           'FlowModelData: LoadFlowAndAuxTimeseries: final time is ', finalTime
         end if
         kfinal = tdisData%CumulativeTimeStepCount
        end if
      end if
      ! Modify values for backward tracking
      if ( backTracking ) then 
        sign   = -1d0
        kdelta = -1 
        ! This verification avoids creating an additional unnecessary interval.
        ! Taking the previous example, if initialTime 1.5dt, and finalTime is dt, 
        ! FindContainingTimeStep returns 2 and 1 respectively, hence nTimeIntervals 
        ! is 2 if computed as abs(kfinal-kinitial)+1, when in reality is only 1 interval.
        if ( finalTime.eq.tdisData%TotalTimes(kfinal) ) correctInterval = 0
      end if
      ! The number of intervals
      nTimeIntervals = abs(kfinal - kinitial) + correctInterval
      nTimes = nTimeIntervals + 1 
      ! Something wrong with times 
      if ( nTimeIntervals .lt. 1 ) then 
        write(message,'(A)')& 
          'Error: the number of times is .lt. 1. Check definition of reference and stoptimes. Stop.'
        message = trim(message)
        call ustop(message)
      end if  
      ! times: includes intial and final times ( reference, stoptime )
      if ( allocated( times ) ) deallocate( times ) 
      allocate( times(nTimes) )
      if ( allocated( timeIntervals ) ) deallocate( timeIntervals ) 
      allocate( timeIntervals(nTimeIntervals) )  
      ! Fill times and time intervals
      if ( backTracking ) then 
        do ktime=1,nTimeIntervals
          if ( ktime .eq. 1 ) times(1) = initialTime
          if ( ktime .lt. nTimeIntervals ) times(ktime+1) = tdisData%TotalTimes(kinitial-ktime)
          if ( ktime .eq. nTimeIntervals ) times(nTimes)  = finalTime 
          timeIntervals(ktime) = abs(times(ktime+1) - times(ktime))
        end do
      else
        do ktime=1,nTimeIntervals
          if ( ktime .eq. 1 ) times(1) = initialTime
          if ( ktime .lt. nTimeIntervals ) times(ktime+1) = tdisData%TotalTimes(ktime+kinitial-1)
          if ( ktime .eq. nTimeIntervals ) times(nTimes)  = finalTime 
          timeIntervals(ktime) = times(ktime+1) - times(ktime)
        end do
      end if 
      ! Number of aux variables
      nAuxVars = size(auxVarNames)
      if ( nAuxVars .lt. 1 ) then 
         write(message,'(A)') 'Error: number of aux variables for timeseries should be at least 1. Stop.'
         message = trim(message)
         call ustop(message)
      end if  

      ! In order to extract the pkg cells, it needs to 
      ! run over stress periods
      ! Get the initial and final stress
      call tdisData%GetPeriodAndStep(kinitial, spInit, tsInit)
      call tdisData%GetPeriodAndStep(kfinal  , spEnd , tsEnd )
      nStressPeriods = abs(spEnd - spInit) + 1
      timeStep = 1

      ! Loop over range of stress periods
      do nsp=1, nStressPeriods

        ! Determine record range for stressPeriod and timeStep
        call this%BudgetReader%GetRecordHeaderRange(nsp, timeStep, firstRecord, lastRecord)

        if(firstRecord .eq. 0) then
          write(message,'(A,I5,A,I5,A)') ' Error loading Time Step ', timeStep, ' Period ', nsp, '.'
          message = trim(message)
          write(*,'(A)') message
          call ustop('Missing budget information. Budget file must have output for every time step. Stop.')
        end if

        ! Loop through record headers
        do n = firstRecord, lastRecord
          header    = this%BudgetReader%GetRecordHeader(n)
          if ( ( header%Method .eq. 5 ) .or. ( header%Method .eq. 6 ) ) then

            ! Is the requested pkg ?
            foundTheSource = .false.

            ! MF6
            if ( isMF6 ) then 
              textLabel = header%TXT2ID2
              call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
              if (&
                textLabel(firstNonBlank:lastNonBlank) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                foundTheSource = .true.
              end if
              ! Try with the budget text label
              if ( .not. foundTheSource ) then 
                textLabel = header%TextLabel
                call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
                if (&
                  textLabel(firstNonBlank:lastNonBlank) .eq. & 
                  sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                  foundTheSource = .true.
                end if 
              end if 
            ! OTHER MODFLOW
            else
              textLabel = header%TextLabel
              call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)

              ! Needs to verify relation
              ! Find equivalence
              nbindex = 0
              do nb=1,nbmax
                textNameLabel = anamebud(nb) 
                call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
                if (&
                  textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                  textLabel(firstNonBlank:lastNonBlank) ) then
                  ! Found, continue
                  nbindex = nb
                  exit
                end if   
              end do

              ! Not found in the list of known budgets supporting
              ! aux variables, try next budget header. It might be useful 
              ! to report the header text label for validation.
              if ( nbindex .eq. 0 ) then
                exit
              end if

              ! Compare the id/ftype (e.g. WEL) against the given src name,
              ! and if not, give it another chance by comparing against the 
              ! budget label itself (e.g. WELLS)
              textNameLabel = anameid(nbindex) 
              call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
              if (&
                textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                foundTheSource = .true.
              else
                textNameLabel = anamebud(nbindex) 
                call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
                if (&
                  textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                  sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                  foundTheSource = .true.
                end if
              end if
            end if ! isMF6

            if ( foundTheSource ) then 
              ! Check cells
              call this%BudgetReader%FillRecordDataBuffer(header,       &
                this%ListItemBuffer, listItemBufferSize, spaceAssigned, &
                status)
              if(spaceAssigned .gt. 0) then
                      
                ! If allocated with different size, reallocate 
                ! else restart indexes
                if ( allocated(spCellNumbers) ) then 
                  if ( size(spCellNumbers) .ne. spaceAssigned ) then 
                    deallocate( spCellNumbers )
                    allocate(spCellNumbers(spaceAssigned))
                    if( lookForIFace ) then 
                      deallocate( spIFaces )
                      allocate(spIFaces(spaceAssigned))
                      spIFaces(:) = 0
                    end if 
                  else
                    spCellNumbers(:) = 0
                    if( lookForIFace ) then 
                      spIFaces(:) = 0
                    end if 
                  end if
                else
                  allocate(spCellNumbers(spaceAssigned))
                  if( lookForIFace ) then 
                    allocate(spIFaces(spaceAssigned))
                    spIFaces(:) = 0
                  end if 
                end if

                ! Assign to stress period cell numbers
                do m = 1, spaceAssigned
                  cellNumber = this%ListItemBuffer(m)%CellNumber
                  spCellNumbers(m) = cellNumber
                end do
                
                ! Again, it is considered that the existence of IFACE 
                ! has been already established, as every other aux var, 
                ! regardless of which value it may have
                if ( lookForIFace ) then 
                  ifaceindex = header%FindAuxiliaryNameIndex('IFACE')
                  if ( ifaceindex .gt. 0 ) then 
                   do m = 1, spaceAssigned
                    spIFaces(m) = int(this%ListItemBuffer(m)%AuxiliaryValues(ifaceindex))
                   end do
                  end if
                end if 

                ! Assign cellNumbers
                if ( .not. allocated( cellNumbers ) ) then
                  ! First initialization
                  allocate( cellNumbers(spaceAssigned) )
                  cellNumbers(:) = spCellNumbers(:)
                  if ( lookForIFace ) then 
                    allocate( iFaceCells(spaceAssigned) )
                    iFaceCells(:) = spIFaces(:)
                  end if 
                  ! Break the records loop and continue to next stress period
                  exit
                else
                  ! If allocated, verify if any new cell
                  newcounter = 0
                  do m =1, spaceAssigned
                    cellindex = findloc( cellNumbers, spCellNumbers(m), 1 ) 
                    if ( cellindex .eq. 0 ) newcounter = newcounter + 1 ! is new cell
                  end do 
                  ! If any new, add it to cellNumbers
                  if ( newcounter .gt. 0 ) then 
                    if ( allocated( tempCellNumbers ) ) deallocate( tempCellNumbers ) 
                    allocate( tempCellNumbers(size(cellNumbers)+newcounter) )
                    tempCellNumbers(1:size(cellNumbers)) = cellNumbers(:) ! save the old
                    if ( lookForIFace ) then 
                      if ( allocated( tempSPIFaces ) ) deallocate( tempSPIFaces ) 
                      allocate( tempSPIFaces(size(iFaceCells)+newcounter) )
                      tempSPIFaces(1:size(iFaceCells)) = iFaceCells(:) ! save the old
                    end if 
                    newcounter = 0
                    do m =1, spaceAssigned
                      cellindex = findloc( cellNumbers, spCellNumbers(m), 1 )
                      if ( cellindex .eq. 0 ) then 
                        newcounter = newcounter + 1 ! is new cell
                        tempCellNumbers(size(cellNumbers)+newcounter) = spCellNumbers(m)
                        if( lookForIFace ) then 
                          tempSPIFaces(size(iFaceCells)+newcounter) = spIFaces(m)
                        end if 
                      end if
                    end do
                    call move_alloc( tempCellNumbers, cellNumbers )
                    if ( lookForIFace ) then 
                      call move_alloc( tempSPIFaces, iFaceCells )
                    end if 
                  end if
                  ! Break the records loop and continue to next stress period
                  exit
                end if !Assign cellNumbers

              end if !if(spaceAssigned .gt. 0)

            end if ! foundTheSource

          end if ! ( header%Method .eq. 5 ) .or. ( header%Method .eq. 6 )

        end do !n = firstRecord, lastRecord

      end do !nsp=1, nStressPeriods

      ! No cells found, something wrong 
      if ( .not. allocated( cellNumbers ) ) then 
         write(message,'(A,A,A)') 'Error: no cells were found for source package ', trim(adjustl(sourcePkgName)), '. Stop.'
         message = trim(message)
         call ustop(message)
      end if  
      nCells = size(cellNumbers)

      ! Allocate arrays for storing timeseries
      if( allocated( flowTimeseries ) ) deallocate( flowTimeseries ) 
      allocate( flowTimeseries( nTimeIntervals, nCells ) )
      flowTimeseries(:,:) = 0d0
      if ( allocated( auxTimeseries ) ) deallocate( auxTimeseries ) 
      allocate( auxTimeseries( nTimeIntervals, nCells, nAuxVars ) )
      auxTimeseries(:,:,:) = 0d0

      ! Use the determined steps (kinitial,kfinal) to build the timeseries
      kcounter = 0
      do ktime = kinitial, kfinal, kdelta

        ! Get the stress period and time step from the cummulative time steps
        call tdisData%GetPeriodAndStep(ktime, stressPeriod, timeStep)
        kcounter = kcounter + 1 

        ! Determine record range for stressPeriod and timeStep
        call this%BudgetReader%GetRecordHeaderRange(stressPeriod, timeStep, firstRecord, lastRecord)
        if(firstRecord .eq. 0) then
          write(message,'(A,I5,A,I5,A)') ' Error loading Time Step ', timeStep, ' Period ', stressPeriod, '.'
          message = trim(message)
          write(*,'(A)') message
          call ustop('Missing budget information. Budget file must have output for every time step. Stop.')
        end if

        ! Loop through record headers
        do n = firstRecord, lastRecord
          header    = this%BudgetReader%GetRecordHeader(n)
          ! Only methods 5,6 support aux variables
          if ( ( header%Method .eq. 5 ) .or. ( header%Method .eq. 6 ) ) then

            ! Is the requested pkg ?
            foundTheSource = .false.

            ! MF6
            if ( isMF6 ) then 
              textLabel = header%TXT2ID2
              call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
              if (&
                textLabel(firstNonBlank:lastNonBlank) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                foundTheSource = .true.
              end if 
              ! Try with the budget text label
              if ( .not. foundTheSource ) then 
                textLabel = header%TextLabel
                call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
                if (&
                  textLabel(firstNonBlank:lastNonBlank) .eq. & 
                  sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                  foundTheSource = .true.
                end if 
              end if 
            ! OTHER MODFLOW
            else
              textLabel = header%TextLabel
              call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)

              ! Needs to verify relation
              ! Find equivalence
              nbindex = 0
              do nb=1,nbmax
                textNameLabel = anamebud(nb) 
                call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
                if (&
                  textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                  textLabel(firstNonBlank:lastNonBlank) ) then
                  ! Found, continue
                  nbindex = nb
                  exit
                end if   
              end do

              ! Not found in the list of known budgets supporting
              ! aux variables, try next budget header. It might be useful 
              ! to report the header text label for validation.
              if ( nbindex .eq. 0 ) then
                exit
              end if

              ! Compare the id/ftype (e.g. WEL) against the given src name,
              ! and if not, give it another chance by comparing against the 
              ! budget label itself (e.g. WELLS)
              textNameLabel = anameid(nbindex) 
              call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
              if (&
                textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                foundTheSource = .true.
              else
                textNameLabel = anamebud(nbindex) 
                call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
                if (&
                  textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                  sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                  foundTheSource = .true.
                end if
              end if
            end if ! isMF6

            if ( foundTheSource ) then 
              ! Found the pkg
              call this%BudgetReader%FillRecordDataBuffer(header,             &
                this%ListItemBuffer, listItemBufferSize, spaceAssigned,       &
                status)
              if(spaceAssigned .gt. 0) then
                do m = 1, spaceAssigned
                  cellNumber = this%ListItemBuffer(m)%CellNumber

                  ! Determine the index of cellNumber in the list of cells 
                  ! requested for timeseseries
                  cellindex = findloc( cellNumbers, cellNumber, 1 ) 
                  if ( cellindex .eq. 0 ) cycle ! Not found, but it should not be the case

                  ! Load into flow rates timeseries only if positive, 
                  ! otherwise leave as zero. Notice that the same 
                  ! applies to concentration. However, because aux var
                  ! could be something else (?), it will save whatever 
                  ! it finds
                  if(sign*this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                    flowTimeseries( kcounter, cellindex ) = sign*this%ListItemBuffer(m)%BudgetValue
                  end if
                  
                  ! Load aux vars
                  do naux=1, nAuxVars
                    auxindex = header%FindAuxiliaryNameIndex(auxVarNames(naux))
                    if(auxindex .gt. 0) then
                      auxTimeseries( kcounter, cellindex, naux ) = this%ListItemBuffer(m)%AuxiliaryValues(auxindex)
                    end if
                  end do

                end do ! spaceAssigned
              end if
              
              ! Break the records loop and continue to next ktime
              exit

            end if ! foundTheSource

          end if ! ( header%Method .eq. 5 ) .or. ( header%Method .eq. 6 ) 

        end do ! n = firstRecord, lastRecord

        ! Break if the number of intervals was reached
        if ( kcounter .eq. nTimeIntervals ) exit

      end do ! ktime=kinitial,kfinal


      if( allocated(tempCellNumbers))deallocate(tempCellNumbers)
      if( allocated(spCellNumbers)  )deallocate(spCellNumbers)


    end subroutine pr_LoadFlowAndAuxTimeseries



    function pr_ValidateAuxVarNames( this, sourcePkgName, auxVarNames, isMF6,& 
                                              iFaceOption ) result ( isValid )
    !------------------------------------------------------------------------
    !
    !------------------------------------------------------------------------
    ! Specifications
    !------------------------------------------------------------------------
    implicit none
    ! input
    class(FlowModelDataType) :: this
    character(len=16), intent(in) :: sourcePkgName
    character(len=20), dimension(:), intent(in) :: auxVarNames
    logical, intent(in) :: isMF6
    logical, optional, intent(in) :: iFaceOption
    ! output
    logical :: isValid
    ! local
    integer :: timeStep = 1 ! to look for aux vars, use as ref...
    integer :: stressPeriod = 1 ! the first stperiod, first tstep
    integer :: n, naux, nx, nval, auxindex
    integer :: firstRecord,lastRecord
    integer :: listItemBufferSize
    integer :: firstNonBlank,lastNonBlank,trimmedLength
    integer :: firstNonBlankIn,lastNonBlankIn,trimmedLengthIn
    integer :: firstNonBlankLoc,lastNonBlankLoc,trimmedLengthLoc
    type(BudgetRecordHeaderType) :: header
    character(len=16)  :: textLabel
    character(len=16)  :: textNameLabel
    character(len=132) :: message
    logical :: lookForIFace = .false.
    integer :: ifaceindex
    integer :: nb, nbindex
    integer :: nbmax = 5
    character(len=16)  :: anamebud(5)
    DATA anamebud(1) /'           WELLS'/ ! WEL
    DATA anamebud(2) /'    DRAINS (DRT)'/ ! DRT
    DATA anamebud(3) /'          DRAINS'/ ! DRN
    DATA anamebud(4) /'   RIVER LEAKAGE'/ ! RIV
    DATA anamebud(5) /' HEAD DEP BOUNDS'/ ! GHB
    character(len=16)  :: anameid(5)
    DATA anameid(1)  /'             WEL'/ ! WEL
    DATA anameid(2)  /'             DRT'/ ! DRT
    DATA anameid(3)  /'             DRN'/ ! DRN
    DATA anameid(4)  /'             RIV'/ ! RIV
    DATA anameid(5)  /'             GHB'/ ! GHB
    !------------------------------------------------------------------------

      ! Check the iface flag
      if ( present( iFaceOption) ) then 
        lookForIface = .false.
        ifaceindex   = 0
        lookForIFace = iFaceOption
      end if 

      ! Initialize output
      isValid = .false.

      ! Trim input pkg type
      call TrimAll(sourcePkgName, firstNonBlankIn, lastNonBlankIn, trimmedLengthIn)

      ! Determine record range for stressPeriod and timeStep
      call this%BudgetReader%GetRecordHeaderRange(stressPeriod, timeStep, firstRecord, lastRecord)
      if(firstRecord .eq. 0) then
        write(message,'(A,I5,A,I5,A)') 'Error: loading Time Step ', timeStep, ' Period ', stressPeriod, '.'
        message = trim(message)
        write(*,'(A)') message
        call ustop('Error: Missing budget information. Budget file must have output for every time step. Stop.')
      end if

      naux = size( auxVarNames )
      listItemBufferSize = size(this%ListItemBuffer) 

      ! For MF6, the easiest validation is to 
      ! verify auxiliary var names by identifying the 
      ! package against TXT2ID2
      if ( isMF6 ) then
        ! Loop through record headers
        do n = firstRecord, lastRecord
          header    = this%BudgetReader%GetRecordHeader(n)
          ! Only methods 5,6 support aux variables
          if ( ( header%Method .eq. 5 ) .or. ( header%Method .eq. 6 ) ) then
            textLabel = header%TXT2ID2
            call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
            if (&
              textLabel(firstNonBlank:lastNonBlank) .eq. & 
              sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
              nval = 0
              do nx =1, naux 
                auxindex = header%FindAuxiliaryNameIndex(auxVarNames(nx)) ! it does a trim
                if(auxindex .gt. 0) then
                  nval = nval + 1
                end if
              end do
              if ( lookForIFace ) then
                ifaceindex = header%FindAuxiliaryNameIndex('IFACE')
                ! Is valid
                if ( (nval .eq. naux) .and. (ifaceindex.gt.0) ) then 
                  isValid = .true.
                  ! Leave 
                  return
                end if
              else
                ! Is valid
                if ( nval .eq. naux ) then 
                  isValid = .true.
                  ! Leave 
                  return
                end if
              end if
            else 
              ! A second chance with the budget text label
              textLabel = header%TextLabel
              call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
              if (&
                textLabel(firstNonBlank:lastNonBlank) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                nval = 0
                do nx =1, naux 
                  auxindex = header%FindAuxiliaryNameIndex(auxVarNames(nx)) ! it does a trim
                  if(auxindex .gt. 0) then
                    nval = nval + 1
                  end if
                end do
                if ( lookForIFace ) then
                  ifaceindex = header%FindAuxiliaryNameIndex('IFACE')
                  ! Is valid
                  if ( (nval .eq. naux) .and. (ifaceindex.gt.0) ) then 
                    isValid = .true.
                    ! Leave 
                    return
                  end if
                else
                  ! Is valid
                  if ( nval .eq. naux ) then 
                    isValid = .true.
                    ! Leave 
                    return
                  end if
                end if
              end if
            end if
          end if ! header method 5,6
        end do
      ! Other MODFLOW flavors
      ! Compare against the list of known headers that accept
      ! aux variables
      else
        ! Loop through record headers
        do n = firstRecord, lastRecord
          header    = this%BudgetReader%GetRecordHeader(n)
          ! Only methods 5,6 support aux variables
          if ( ( header%Method .eq. 5 ) .or. ( header%Method .eq. 6 ) ) then
            textLabel = header%TextLabel
            call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)

            ! Needs to verify relation
            ! Find equivalence
            nbindex = 0
            do nb=1,nbmax
              textNameLabel = anamebud(nb) 
              call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
              if (&
                textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                textLabel(firstNonBlank:lastNonBlank) ) then
                ! Found, continue
                nbindex = nb
                exit
              end if   
            end do

            ! Not found in the list of known budgets supporting
            ! aux variables, try next budget header. It might be useful 
            ! to report the header text label for validation.
            if ( nbindex .eq. 0 ) then
              exit
            end if

            ! Compare the id/ftype (e.g. WEL) against the given src name,
            ! and if not, give it another chance by comparing against the 
            ! budget label itself (e.g. WELLS)
            textNameLabel = anameid(nbindex) 
            call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
            if (&
              textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
              sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
              nval = 0
              do nx =1, naux 
                auxindex = header%FindAuxiliaryNameIndex(auxVarNames(nx)) ! it does a trim
                if(auxindex .gt. 0) then
                  nval = nval + 1
                end if
              end do
              if ( lookForIFace ) then
                ifaceindex = header%FindAuxiliaryNameIndex('IFACE')
                ! Is valid
                if ( (nval .eq. naux) .and. (ifaceindex.gt.0) ) then 
                  isValid = .true.
                  ! Leave 
                  return
                end if
              else
                ! Is valid
                if ( nval .eq. naux ) then 
                  isValid = .true.
                  ! Leave 
                  return
                end if
              end if
            else
              textNameLabel = anamebud(nbindex) 
              call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
              if (&
                textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                nval = 0
                do nx =1, naux 
                  auxindex = header%FindAuxiliaryNameIndex(auxVarNames(nx)) ! it does a trim
                  if(auxindex .gt. 0) then
                    nval = nval + 1
                  end if
                end do
                if ( lookForIFace ) then
                  ifaceindex = header%FindAuxiliaryNameIndex('IFACE')
                  ! Is valid
                  if ( (nval .eq. naux) .and. (ifaceindex.gt.0) ) then 
                    isValid = .true.
                    ! Leave 
                    return
                  end if
                else
                  ! Is valid
                  if ( nval .eq. naux ) then 
                    isValid = .true.
                    ! Leave 
                    return
                  end if
                end if
              end if
            end if
          end if ! ( header%Method .eq. 5 ) .or. ( header%Method .eq. 6 )

        end do ! n = firstRecord, lastRecord

      end if 


      ! Done
      return


    end function pr_ValidateAuxVarNames


    function pr_ValidateBudgetHeader( this, sourcePkgName, initialTime,& 
                  finalTime, tdisData, outUnit, backwardTracking, isMF6 ) result ( isValid )
    !------------------------------------------------------------------------
    !
    !------------------------------------------------------------------------
    ! Specifications
    !------------------------------------------------------------------------
    implicit none
    ! input
    class(FlowModelDataType) :: this
    character(len=16), intent(in) :: sourcePkgName
    doubleprecision, optional, intent(in) :: initialTime, finalTime
    class( TimeDiscretizationDataType ), optional, intent(in) :: tdisData
    integer, optional, intent(in) :: outUnit
    logical, optional, intent(in) :: backwardTracking
    logical, optional, intent(in) :: isMF6
    ! output
    logical :: isValid
    ! local
    integer :: timeStep = 1 ! to look for aux vars, use as ref the first tstep 
    integer :: stressPeriod ! the first stperiod, first tstep
    integer :: n
    integer :: firstRecord,lastRecord
    integer :: firstNonBlank,lastNonBlank,trimmedLength
    integer :: firstNonBlankIn,lastNonBlankIn,trimmedLengthIn
    integer :: firstNonBlankLoc,lastNonBlankLoc,trimmedLengthLoc
    type(BudgetRecordHeaderType) :: header
    character(len=16)  :: textLabel
    character(len=16)  :: textNameLabel
    character(len=132) :: message
    integer :: kfinal, kinitial
    integer :: spInit, spEnd, tsInit, tsEnd
    integer :: nsp
    integer :: nStressPeriods, nTimeIntervals, nTimes
    logical :: backTracking   = .false.
    logical :: isMF6Budget    = .false.
    integer :: correctInterval
    integer :: nb
    integer :: nbmax = 6
    character(len=16)  :: anamebud(6)
    DATA anamebud(1) /'           WELLS'/ ! WEL
    DATA anamebud(2) /'    DRAINS (DRT)'/ ! DRT
    DATA anamebud(3) /'          DRAINS'/ ! DRN
    DATA anamebud(4) /'   RIVER LEAKAGE'/ ! RIV
    DATA anamebud(5) /' HEAD DEP BOUNDS'/ ! GHB
    DATA anamebud(6) /'        RECHARGE'/ ! RCH
    character(len=16)  :: anameid(6)
    DATA anameid(1)  /'             WEL'/ ! WEL
    DATA anameid(2)  /'             DRT'/ ! DRT
    DATA anameid(3)  /'             DRN'/ ! DRN
    DATA anameid(4)  /'             RIV'/ ! RIV
    DATA anameid(5)  /'             GHB'/ ! GHB
    DATA anameid(6)  /'             RCH'/ ! RCH
    !------------------------------------------------------------------------


      ! Initialize output
      isValid = .false.

      ! Trim input pkg/header name 
      call TrimAll(sourcePkgName, firstNonBlankIn, lastNonBlankIn, trimmedLengthIn)

      isMF6Budget = .false.
      if ( present( isMF6 ) ) then 
        if ( isMF6 ) isMF6Budget = .true.
      end if 

      if( present( initialTime ) .or. present( finalTime ) ) then 
        ! If times given verify header existence for a range of stress periods

        if (.not. present( tdisData ) ) then 
        write(message,'(A)')& 
          'FlowModelData: ValidateBudgetHeader: when any time is given, it also requires tdisData. Stop.'
        message = trim(message)
        call ustop(message)
        end if

        correctInterval = 1
        backTracking = .false.
        if ( present( backwardTracking ) ) then
          if ( backwardTracking ) backTracking = .true. 
        end if 

        ! Given initial and final times, 
        ! compute the initial and final time step indexes
        if( present( initialTime ) ) then 
          kinitial = tdisData%FindContainingTimeStep(initialTime)
        else
         if ( backTracking ) then  
           kinitial = tdisData%CumulativeTimeStepCount
         else
           kinitial = 1
         end if 
        end if 
        if( present( finalTime ) ) then 
          kfinal   = tdisData%FindContainingTimeStep(finalTime)
          if ( backTracking ) then 
            if ( (kfinal .eq. 0) ) then
             if ( present(outUnit) ) then       
              write(outUnit,'(a)') 'FlowModelData: ValidateBudgetHeader: kfinal is assumed to be 1.'
              write(outUnit,'(a,e15.7)') 'FlowModelData: ValidateBudgetHeader: final time is ', finalTime
             end if
             kfinal = 1
            end if
          else
            if ( (kfinal .eq. 0) ) then
             if ( present(outUnit) ) then       
              write(outUnit,'(a)') &
                'FlowModelData: ValidateBudgetHeader: kfinal is assumed to be CumulativeTimeStepCount.'
              write(outUnit,'(a,e15.7)') 'FlowModelData: ValidateBudgetHeader: final time is ', finalTime
             end if
             kfinal = tdisData%CumulativeTimeStepCount
            end if
          end if
        else
         if ( backTracking ) then  
           kfinal = 1
         else 
           kfinal = tdisData%CumulativeTimeStepCount
         end if 
        end if 
   
        ! Modify values for backward tracking
        if ( backTracking ) then 
          ! This verification avoids creating an additional unnecessary interval.
          ! Taking the previous example, if initialTime 1.5dt, and finalTime is dt, 
          ! FindContainingTimeStep returns 2 and 1 respectively, hence nTimeIntervals 
          ! is 2 if computed as abs(kfinal-kinitial)+1, when in reality is only 1 interval.
          if ( finalTime.eq.tdisData%TotalTimes(kfinal) ) correctInterval = 0
        end if

        ! The number of intervals
        nTimeIntervals = abs(kfinal - kinitial) + correctInterval
        nTimes = nTimeIntervals + 1 
        ! Something wrong with times 
        if ( nTimeIntervals .lt. 1 ) then 
         write(message,'(A)')& 
           'Error: the number of times is .lt. 1. Check definition of reference and stoptimes. Stop.'
         message = trim(message)
         call ustop(message)
        end if  

        ! Get the initial and final stress
        call tdisData%GetPeriodAndStep(kinitial, spInit, tsInit)
        call tdisData%GetPeriodAndStep(kfinal  , spEnd , tsEnd )
        nStressPeriods = abs(spEnd - spInit) + 1
        timeStep = 1
      else
        ! If no time information given, verify against the first
        nStressPeriods = 1
        timeStep = 1
      end if 


      ! Loop over the range of stress periods. 
      ! It needs to find it only once, so return as soon as found. 
      do nsp=1, nStressPeriods

        ! Determine record range for stressPeriod and timeStep
        call this%BudgetReader%GetRecordHeaderRange(nsp, timeStep, firstRecord, lastRecord)
        if(firstRecord .eq. 0) then
          write(message,'(A,I5,A,I5,A)') ' Error loading Time Step ', timeStep, ' Period ', stressPeriod, '.'
          message = trim(message)
          write(*,'(A)') message
          call ustop('Missing budget information. Budget file must have output for every time step. Stop.')
        end if

        ! Loop through record headers
        do n = firstRecord, lastRecord
          header    = this%BudgetReader%GetRecordHeader(n)
          textLabel = header%TextLabel
          call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
          if (&
            textLabel(firstNonBlank:lastNonBlank) .eq. & 
            sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
            ! Found it
            isValid = .true.
            return
          end if

          ! A second chance for mf6
          if ( isMF6Budget .and. ( .not. isValid ) ) then 
            textLabel = header%TXT2ID2
            call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
            ! If the TXT2ID2 label not empty, verify
            if ( trimmedLength .gt. 0 ) then 
              if (&
                textLabel(firstNonBlank:lastNonBlank) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                ! Found it
                isValid = .true.
                return
              end if
            end if
          end if 

          ! A second chance for other MODFLOW, trying from anamebud
          if ( ( .not. isMF6Budget ) .and. ( .not. isValid ) ) then 
            ! Verify if the given source name (short) is in the list 
            ! of known budgets names (longnames)
            do nb=1,nbmax
              textNameLabel = anameid(nb) 
              call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
              if (&
                textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                ! Found it
                isValid = .true.
                return
              end if   
            end do
          end if 

        end do ! n = firstRecord, lastRecord

      end do !nsp=1, nStressPeriods


      ! Done
      return


    end function pr_ValidateBudgetHeader


    subroutine pr_LoadFlowTimeseries(this, sourcePkgName, & 
                        initialTime, finalTime, tdisData, &
                             cellNumbers, flowTimeseries, &
                            readCellsFromBudget, outUnit, & 
                                        backwardTracking, &
                                                   isMF6  )
    !------------------------------------------------------------------------
    ! Given a range of times, extract a flow-rates timeseries from the header 
    ! sourcePkgName, only for cells in cellNumbers and positive flow-rates.
    ! The latter because these are used for determining injected solute mass. 
    !
    ! It can optionally receive readCellsFromBudget, which will perform a 
    ! preliminary detection of cells for the given pkg/name.
    !  
    !------------------------------------------------------------------------
    ! Specifications
    !------------------------------------------------------------------------
    implicit none
    ! input
    class(FlowModelDataType) :: this
    character(len=16), intent(in) :: sourcePkgName
    doubleprecision, intent(in)   :: initialTime, finalTime
    class( TimeDiscretizationDataType ), intent(in) :: tdisData
    integer, allocatable, dimension(:), intent(inout) :: cellNumbers
    logical, optional, intent(in) :: readCellsFromBudget
    integer, optional, intent(in) :: outUnit
    logical, optional, intent(in) :: backwardTracking
    logical, optional, intent(in) :: isMF6
    ! out
    doubleprecision, allocatable, dimension(:,:)  , intent(inout) :: flowTimeseries ! nt x ncells
    ! local
    integer :: n, m
    integer :: stressPeriod, timeStep
    integer :: firstRecord,lastRecord
    integer :: firstNonBlank,lastNonBlank,trimmedLength
    integer :: firstNonBlankIn,lastNonBlankIn,trimmedLengthIn
    integer :: firstNonBlankLoc,lastNonBlankLoc,trimmedLengthLoc
    integer :: spaceAssigned, status, cellCount, cellindex
    integer :: listItemBufferSize, cellNumber
    type(BudgetRecordHeaderType) :: header
    character(len=16)  :: textLabel
    character(len=16)  :: textNameLabel
    character(len=132) :: message
    integer :: nCells, newcounter
    integer :: kinitial, kfinal, ktime, kcounter, kdelta
    integer :: nTimes, nTimeIntervals, cellCounter 
    integer :: spInit, tsInit, spEnd, tsEnd, nStressPeriods, nsp 
    integer, allocatable, dimension(:) :: tempCellNumbers
    integer, allocatable, dimension(:) :: spCellNumbers
    logical :: readCells
    logical :: backTracking   = .false.
    integer :: correctInterval
    logical :: foundTheSource = .false.
    logical :: isMF6Budget    = .false.
    doubleprecision :: sign
    integer :: nb
    integer :: nbmax = 6
    character(len=16)  :: anamebud(6)
    DATA anamebud(1) /'           WELLS'/ ! WEL
    DATA anamebud(2) /'    DRAINS (DRT)'/ ! DRT
    DATA anamebud(3) /'          DRAINS'/ ! DRN
    DATA anamebud(4) /'   RIVER LEAKAGE'/ ! RIV
    DATA anamebud(5) /' HEAD DEP BOUNDS'/ ! GHB
    DATA anamebud(6) /'        RECHARGE'/ ! RCH
    character(len=16)  :: anameid(6)
    DATA anameid(1)  /'             WEL'/ ! WEL
    DATA anameid(2)  /'             DRT'/ ! DRT
    DATA anameid(3)  /'             DRN'/ ! DRN
    DATA anameid(4)  /'             RIV'/ ! RIV
    DATA anameid(5)  /'             GHB'/ ! GHB
    DATA anameid(6)  /'             RCH'/ ! RCH
    !------------------------------------------------------------------------

      ! Trim input pkg name
      call TrimAll(sourcePkgName, firstNonBlankIn, lastNonBlankIn, trimmedLengthIn)
      cellCount = this%Grid%CellCount
      listItemBufferSize = size(this%ListItemBuffer)

      isMF6Budget = .false.
      if ( present ( isMF6 ) ) then 
        if ( isMF6 ) isMF6Budget = .true.
      end if 

      ! Determine the sign to consider for the source, for 
      ! compatibility with backward tracking.
      sign   = 1d0
      kdelta = 1
      correctInterval = 1
      backTracking = .false.
      if ( present( backwardTracking ) ) then
        if ( backwardTracking ) backTracking = .true. 
      end if 

      ! Given initial and final times, 
      ! compute the initial and final time step indexes
      kinitial = tdisData%FindContainingTimeStep(initialTime)
      kfinal   = tdisData%FindContainingTimeStep(finalTime)
      if ( backTracking ) then 
        if ( (kfinal .eq. 0) ) then
         if ( present(outUnit) ) then       
          write(outUnit,'(a)') 'FlowModelData: LoadFlowTimeseries: kfinal is assumed to be 1.'
          write(outUnit,'(a,e15.7)') 'FlowModelData: LoadFlowTimeseries: final time is ', finalTime
         end if
         kfinal = 1 
        end if
      else
        if ( (kfinal .eq. 0) ) then
         if ( present(outUnit) ) then       
          write(outUnit,'(a)') 'FlowModelData: LoadFlowTimeseries: kfinal is assumed to be CumulativeTimeStepCount.'
          write(outUnit,'(a,e15.7)') 'FlowModelData: LoadFlowTimeseries: final time is ', finalTime
         end if
         kfinal = tdisData%CumulativeTimeStepCount
        end if
      end if

      ! Modify values for backward tracking
      if ( backTracking ) then 
        sign   = -1d0
        kdelta = -1 
        ! This verification avoids creating an additional unnecessary interval.
        ! Taking the previous example, if initialTime 1.5dt, and finalTime is dt, 
        ! FindContainingTimeStep returns 2 and 1 respectively, hence nTimeIntervals 
        ! is 2 if computed as abs(kfinal-kinitial)+1, when in reality is only 1 interval.
        if ( finalTime.eq.tdisData%TotalTimes(kfinal) ) correctInterval = 0
      end if

      ! The number of intervals
      nTimeIntervals = abs(kfinal - kinitial) + correctInterval
      nTimes = nTimeIntervals + 1 
      ! Something wrong with times 
      if ( nTimeIntervals .lt. 1 ) then 
        write(message,'(A)') 'Error: the number of times is .lt. 1. Check definition of reference and stoptimes. Stop.'
        message = trim(message)
        call ustop(message)
      end if  
        
      ! Interpret readcells
      readCells = .false.
      if ( present( readCellsFromBudget ) ) then 
        readCells = readCellsFromBudget 
      end if 

      ! Ok, read cells from budget
      if ( readCells ) then

        ! Start by deallocating any given cellNumbers
        if( allocated( cellNumbers ) ) deallocate( cellNumbers ) 
        
        ! Get the initial and final stress
        call tdisData%GetPeriodAndStep(kinitial, spInit, tsInit)
        call tdisData%GetPeriodAndStep(kfinal  , spEnd , tsEnd )
        nStressPeriods = abs(spEnd - spInit) + 1
        timeStep = 1

        ! Loop over range of stress periods
        do nsp=1, nStressPeriods

          ! Determine record range for stressPeriod and timeStep
          call this%BudgetReader%GetRecordHeaderRange(nsp, timeStep, firstRecord, lastRecord)

          if(firstRecord .eq. 0) then
            write(message,'(A,I5,A,I5,A)') ' Error loading Time Step ', timeStep, ' Period ', nsp, '.'
            message = trim(message)
            write(*,'(A)') message
            call ustop('Missing budget information. Budget file must have output for every time step. Stop.')
          end if

          ! Loop through record headers
          do n = firstRecord, lastRecord
            header    = this%BudgetReader%GetRecordHeader(n)
            textLabel = header%TextLabel
            call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)

            ! Is the requested pkg ?
            foundTheSource = .false.
            if (&
              textLabel(firstNonBlank:lastNonBlank) .eq. & 
              sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
              ! Found it
              foundTheSource = .true.
            end if 

            ! A second chance for mf6
            if ( isMF6Budget .and. ( .not. foundTheSource ) ) then 
              textLabel = header%TXT2ID2
              call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
              ! If the TXT2ID2 label not empty, verify
              if ( trimmedLength .gt. 0 ) then 
                if (&
                  textLabel(firstNonBlank:lastNonBlank) .eq. & 
                  sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                  ! Found it
                  foundTheSource = .true.
                end if
              end if
            end if 

            ! A second chance for other MODFLOW, trying from anamebud
            if ( ( .not. isMF6Budget ) .and. ( .not. foundTheSource ) ) then 
              ! Verify if the given source name (short) is in the list 
              ! of known budgets names (longnames)
              do nb=1,nbmax
                textNameLabel = anameid(nb) 
                call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
                if (&
                  textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                  sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                  ! Found it
                  foundTheSource = .true.
                  ! Assign textLabel to the found longname
                  textLabel = anamebud(nb) 
                  ! Calculate the extent in text, using the longname
                  call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
                  exit
                end if   
              end do
            end if


            if ( foundTheSource ) then 
              ! Read accordingly
              select case(header%Method) 
              case(0,1)
                ! Header methods 0,1 should somehow count which 
                ! cells have non-zero positive flow-rates otherwise
                ! will allocate everything
                select case(textLabel(firstNonBlank:lastNonBlank))
                  case('CONSTANT HEAD', 'CHD')
                    call this%BudgetReader%FillRecordDataBuffer(header, &
                                        this%ArrayBufferDbl, cellCount, & 
                                                  spaceAssigned, status )
                    if(cellCount .eq. spaceAssigned) then
                      ! Count cells with positive flow-rate
                      ! Restart cellCounter
                      cellCounter = 0
                      do m = 1, spaceAssigned
                        if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                          cellCounter = cellCounter + 1
                        end if
                      end do
                      if ( cellCounter .eq. 0 ) exit
                      ! If allocated with different size, reallocate 
                      ! else restart indexes
                      if ( allocated(spCellNumbers) ) then 
                        if ( size(spCellNumbers) .ne. cellCounter ) then 
                          deallocate( spCellNumbers )
                          allocate(spCellNumbers(cellCounter))
                        else
                          spCellNumbers(:) = 0
                        end if
                      else
                        allocate(spCellNumbers(cellCounter))
                      end if
                      ! Assign to stress period cell numbers
                      cellCounter = 0
                      do m = 1, spaceAssigned
                        if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                          cellCounter = cellCounter + 1
                          cellNumber  = m 
                          spCellNumbers(m) = cellNumber
                        end if
                      end do
                    end if ! if(cellCount .eq. spaceAssigned)
                  case default
                    if(header%ArrayItemCount .eq. cellCount) then
                      call this%BudgetReader%FillRecordDataBuffer(header, &
                                          this%ArrayBufferDbl, cellCount, & 
                                                    spaceAssigned, status )
                      if(cellCount .eq. spaceAssigned) then
                        ! Count cells with positive flow-rate
                        ! Restart cellCounter
                        cellCounter = 0
                        do m = 1, spaceAssigned
                          if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                            cellCounter = cellCounter + 1
                          end if
                        end do
                        if ( cellCounter .eq. 0 ) exit

                        ! If allocated with different size, reallocate 
                        ! else restart indexes
                        if ( allocated(spCellNumbers) ) then 
                          if ( size(spCellNumbers) .ne. cellCounter ) then 
                            deallocate( spCellNumbers )
                            allocate(spCellNumbers(cellCounter))
                          else
                            spCellNumbers(:) = 0
                          end if
                        else
                          allocate(spCellNumbers(cellCounter))
                        end if
                        ! Assign to stress period cell numbers
                        cellCounter = 0
                        do m = 1, spaceAssigned
                          if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                            cellCounter = cellCounter + 1
                            cellNumber  = m 
                            spCellNumbers(m) = cellNumber
                          end if
                        end do
                      end if ! if(cellCount .eq. spaceAssigned)
                    end if
                end select
              case(2)
                call this%BudgetReader%FillRecordDataBuffer(header, &
                           this%ListItemBuffer, listItemBufferSize, & 
                                              spaceAssigned, status )
                if(spaceAssigned .gt. 0) then
                  ! Count cells with positive flow-rate
                  ! Restart cellCounter
                  cellCounter = 0
                  do m = 1, spaceAssigned
                    if(sign*this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                      cellCounter = cellCounter + 1
                    end if
                  end do
                  if ( cellCounter .eq. 0 ) exit
                  ! If allocated with different size, reallocate 
                  ! else restart indexes
                  if ( allocated(spCellNumbers) ) then 
                    if ( size(spCellNumbers) .ne. cellCounter ) then 
                      deallocate( spCellNumbers )
                      allocate(spCellNumbers(cellCounter))
                    else
                      spCellNumbers(:) = 0
                    end if
                  else
                    allocate(spCellNumbers(cellCounter))
                  end if
                  ! Assign to stress period cell numbers
                  cellCounter = 0 
                  do m = 1, spaceAssigned
                    if(sign*this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                      cellCounter = cellCounter + 1
                      cellNumber = this%ListItemBuffer(m)%CellNumber
                      spCellNumbers(cellCounter) = cellNumber
                    end if
                  end do
                end if ! if(spaceAssigned .gt. 0)
              case(3)
                call this%BudgetReader%FillRecordDataBuffer(header, &
                          this%ArrayBufferDbl, this%ArrayBufferInt, &
                       header%ArrayItemCount, spaceAssigned, status )
                if(header%ArrayItemCount .eq. spaceAssigned) then
                  ! Count cells with positive flow-rate
                  ! Restart cellCounter
                  cellCounter = 0
                  do m = 1, spaceAssigned
                    if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                      cellCounter = cellCounter + 1
                    end if
                  end do
                  if ( cellCounter .eq. 0 ) exit
                  ! If allocated with different size, reallocate 
                  ! else restart indexes
                  if ( allocated(spCellNumbers) ) then 
                    if ( size(spCellNumbers) .ne. cellCounter ) then 
                      deallocate( spCellNumbers )
                      allocate(spCellNumbers(cellCounter))
                    else
                      spCellNumbers(:) = 0
                    end if
                  else
                    allocate(spCellNumbers(cellCounter))
                  end if
                  ! Assign to stress period cell numbers
                  cellCounter = 0
                  do m = 1, spaceAssigned
                    if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                      cellCounter = cellCounter + 1
                      cellNumber = this%ArrayBufferInt(m)
                      spCellNumbers(m) = cellNumber
                    end if
                  end do
                end if ! (header%ArrayItemCount .eq. spaceAssigned) 
              case(4)
                call this%BudgetReader%FillRecordDataBuffer(header, &
                        this%ArrayBufferDbl, header%ArrayItemCount, & 
                                               spaceAssigned,status )
                if(header%ArrayItemCount .eq. spaceAssigned) then
                  ! Count cells with positive flow-rate
                  ! Restart cellCounter
                  cellCounter = 0
                  do m = 1, spaceAssigned
                    if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                      cellCounter = cellCounter + 1
                    end if
                  end do
                  if ( cellCounter .eq. 0 ) exit
                  ! If allocated with different size, reallocate 
                  ! else restart indexes
                  if ( allocated(spCellNumbers) ) then 
                    if ( size(spCellNumbers) .ne. cellCounter ) then 
                      deallocate( spCellNumbers )
                      allocate(spCellNumbers(cellCounter))
                    else
                      spCellNumbers(:) = 0
                    end if
                  else
                    allocate(spCellNumbers(cellCounter))
                  end if
                  ! Assign to stress period cell numbers
                  cellCounter = 0
                  do m = 1, spaceAssigned
                    if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                      cellCounter = cellCounter + 1
                      cellNumber  = m 
                      spCellNumbers(m) = cellNumber
                    end if
                  end do
                end if !(header%ArrayItemCount .eq. spaceAssigned)
              case(5,6)
                call this%BudgetReader%FillRecordDataBuffer(header, &
                           this%ListItemBuffer, listItemBufferSize, &
                                              spaceAssigned, status )
                if(spaceAssigned .gt. 0) then
                  ! Count cells with positive flow-rate
                  ! Restart cellCounter
                  cellCounter = 0
                  do m = 1, spaceAssigned
                    if(sign*this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                      cellCounter = cellCounter + 1
                    end if
                  end do
                  if ( cellCounter .eq. 0 ) exit
                  ! If allocated with different size, reallocate 
                  ! else restart indexes
                  if ( allocated(spCellNumbers) ) then 
                    if ( size(spCellNumbers) .ne. cellCounter ) then 
                      deallocate( spCellNumbers )
                      allocate(spCellNumbers(cellCounter))
                    else
                      spCellNumbers(:) = 0
                    end if
                  else
                    allocate(spCellNumbers(cellCounter))
                  end if
                  ! Assign to stress period cell numbers
                  cellCounter = 0 
                  do m = 1, spaceAssigned
                    if(sign*this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                      cellCounter = cellCounter + 1
                      cellNumber = this%ListItemBuffer(m)%CellNumber
                      spCellNumbers(cellCounter) = cellNumber
                    end if
                  end do
                end if !if(spaceAssigned .gt. 0)

              end select


              ! Assign cellNumbers
              if ( .not. allocated( cellNumbers ) ) then
                ! First initialization
                allocate( cellNumbers(size(spCellNumbers)) )
                cellNumbers(:) = spCellNumbers(:)
                ! Break the records loop and continue to next stress period
                exit
              else
                ! If allocated, verify if any new cell
                newcounter = 0
                do m =1, size(spCellNumbers)
                  cellindex = findloc( cellNumbers, spCellNumbers(m), 1 ) 
                  if ( cellindex .eq. 0 ) newcounter = newcounter + 1 ! is new cell
                end do 
                ! If any new, add it to cellNumbers
                if ( newcounter .gt. 0 ) then 
                  if ( allocated( tempCellNumbers ) ) deallocate( tempCellNumbers ) 
                  allocate( tempCellNumbers(size(cellNumbers)+newcounter) )
                  tempCellNumbers(1:size(cellNumbers)) = cellNumbers(:) ! save the old
                  newcounter = 0
                  do m =1, size(spCellNumbers)
                    cellindex = findloc( cellNumbers, spCellNumbers(m), 1 )
                    if ( cellindex .eq. 0 ) then 
                      newcounter = newcounter + 1 ! is new cell
                      tempCellNumbers(size(cellNumbers)+newcounter) = spCellNumbers(m)
                    end if
                  end do
                  call move_alloc( tempCellNumbers, cellNumbers )
                end if
                ! Break the records loop and continue to next stress period
                exit
              end if !Assign cellNumbers

            end if ! found src pkg name

          end do !n = firstRecord, lastRecord

        end do !nsp=1, nStressPeriods

        ! No cells found, something wrong 
        if ( .not. allocated( cellNumbers ) ) then 
           write(message,'(A,A,A)') 'Error: no cells were found for source package ', trim(adjustl(sourcePkgName)), '. Stop.'
           message = trim(message)
           call ustop(message)
        end if

        ! Clean
        if( allocated(tempCellNumbers))deallocate(tempCellNumbers)
        if( allocated(spCellNumbers)  )deallocate(spCellNumbers)

      end if ! readCells


      ! No cells given, something wrong 
      if ( .not. allocated( cellNumbers ) ) then 
         write(message,'(A,A,A)') 'Error: no cells were given for source package ', trim(adjustl(sourcePkgName)), '. Stop.'
         message = trim(message)
         call ustop(message)
      end if
      nCells = size(cellNumbers)
      if ( nCells .lt. 1 ) then 
         write(message,'(A,A,A)') 'Error: no cells were given for source package ', trim(adjustl(sourcePkgName)), '. Stop.'
         message = trim(message)
         call ustop(message)
      end if


      ! Allocate flowTimeseries and extract POSITIVE flow-rates for the set of cells.
      if ( allocated( flowTimeseries ) ) deallocate( flowTimeseries ) 
      allocate( flowTimeseries( nTimes, nCells ) )
      flowTimeseries(:,:) = 0d0


      ! Use the determined steps (kinitial,kfinal) to build the timeseries
      kcounter = 0
      do ktime = kinitial, kfinal, kdelta

        ! Get the stress period and time step from the cummulative time steps
        call tdisData%GetPeriodAndStep(ktime, stressPeriod, timeStep)
        kcounter = kcounter + 1 

        ! Determine record range for stressPeriod and timeStep
        call this%BudgetReader%GetRecordHeaderRange(stressPeriod, timeStep, firstRecord, lastRecord)
        if(firstRecord .eq. 0) then
          write(message,'(A,I5,A,I5,A)') ' Error loading Time Step ', timeStep, ' Period ', stressPeriod, '.'
          message = trim(message)
          write(*,'(A)') message
          call ustop('Missing budget information. Budget file must have output for every time step. Stop.')
        end if

        ! Loop through record headers
        do n = firstRecord, lastRecord
          header    = this%BudgetReader%GetRecordHeader(n)
          textLabel = header%TextLabel
          call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)

          ! Is the requested pkg ?
          foundTheSource = .false.
          if (&
            textLabel(firstNonBlank:lastNonBlank) .eq. & 
            sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
            ! Found it
            foundTheSource = .true.
          end if 

          ! A second chance for mf6
          if ( isMF6Budget .and. ( .not. foundTheSource ) ) then 
            textLabel = header%TXT2ID2
            call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
            ! If the TXT2ID2 label not empty, verify
            if ( trimmedLength .gt. 0 ) then 
              if (&
                textLabel(firstNonBlank:lastNonBlank) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                ! Found it
                foundTheSource = .true.
              end if
            end if
          end if 

          ! A second chance for other MODFLOW, trying from anamebud
          if ( ( .not. isMF6Budget ) .and. ( .not. foundTheSource ) ) then 
            ! Verify if the given source name (short) is in the list 
            ! of known budgets names (longnames)
            do nb=1,nbmax
              textNameLabel = anameid(nb) 
              call TrimAll(textNameLabel, firstNonBlankLoc, lastNonBlankLoc, trimmedLengthLoc)
              if (&
                textNameLabel(firstNonBlankLoc:lastNonBlankLoc) .eq. & 
                sourcePkgName(firstNonBlankIn:lastNonBlankIn) ) then
                ! Found it
                foundTheSource = .true.
                ! Assign textLabel to the found longname
                textLabel = anamebud(nb) 
                ! Calculate the extent in text, using the longname
                call TrimAll(textLabel, firstNonBlank, lastNonBlank, trimmedLength)
                exit
              end if   
            end do
          end if


          if ( foundTheSource ) then 
            ! Read accordingly
            select case(header%Method) 
            case(0,1)
              select case(textLabel(firstNonBlank:lastNonBlank))
                case('CONSTANT HEAD', 'CHD')
                  call this%BudgetReader%FillRecordDataBuffer(header, &
                                      this%ArrayBufferDbl, cellCount, & 
                                                spaceAssigned, status )
                  if(cellCount .eq. spaceAssigned) then
                    do m = 1, spaceAssigned
                      cellNumber = m 
                      ! Determine the index of cellNumber
                      cellindex  = findloc( cellNumbers, cellNumber, 1 ) 
                      if ( cellindex .eq. 0 ) cycle ! Not requested
                      ! Load into flow rates timeseries only if positive
                      if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                        flowTimeseries( kcounter, cellindex ) = sign*this%ArrayBufferDbl(m)
                      end if
                    end do
                  end if
                case default
                  if(header%ArrayItemCount .eq. cellCount) then
                    call this%BudgetReader%FillRecordDataBuffer(header, &
                                        this%ArrayBufferDbl, cellCount, & 
                                                  spaceAssigned, status )
                    if(cellCount .eq. spaceAssigned) then
                      do m = 1, spaceAssigned
                        cellNumber = m 
                        ! Determine the index of cellNumber
                        cellindex  = findloc( cellNumbers, cellNumber, 1 ) 
                        if ( cellindex .eq. 0 ) cycle ! Not requested
                        ! Load into flow rates timeseries only if positive
                        if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                          flowTimeseries( kcounter, cellindex ) = sign*this%ArrayBufferDbl(m)
                        end if
                      end do
                    end if
                  end if
              end select
            case(2)
              call this%BudgetReader%FillRecordDataBuffer(header, &
                         this%ListItemBuffer, listItemBufferSize, & 
                                            spaceAssigned, status )
              if(spaceAssigned .gt. 0) then
                do m = 1, spaceAssigned
                  cellNumber = this%ListItemBuffer(m)%CellNumber
                  ! Determine the index of cellNumber
                  cellindex  = findloc( cellNumbers, cellNumber, 1 ) 
                  if ( cellindex .eq. 0 ) cycle ! Not requested
                  ! Load into flow rates timeseries only if positive
                  if(sign*this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                    flowTimeseries( kcounter, cellindex ) = sign*this%ListItemBuffer(m)%BudgetValue
                  end if
                end do
              end if
            case(3)
              call this%BudgetReader%FillRecordDataBuffer(header, &
                        this%ArrayBufferDbl, this%ArrayBufferInt, &
                     header%ArrayItemCount, spaceAssigned, status )
              if(header%ArrayItemCount .eq. spaceAssigned) then
                do m = 1, spaceAssigned
                  cellNumber = this%ArrayBufferInt(m)
                  ! Determine the index of cellNumber
                  cellindex  = findloc( cellNumbers, cellNumber, 1 ) 
                  if ( cellindex .eq. 0 ) cycle ! Not requested
                  ! Load into flow rates timeseries only if positive
                  if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                    flowTimeseries( kcounter, cellindex ) = sign*this%ArrayBufferDbl(m)
                  end if
                end do
              end if
            case(4)
              call this%BudgetReader%FillRecordDataBuffer(header, &
                      this%ArrayBufferDbl, header%ArrayItemCount, & 
                                             spaceAssigned,status )
              if(header%ArrayItemCount .eq. spaceAssigned) then
                do m = 1, spaceAssigned
                  cellNumber = m 
                  ! Determine the index of cellNumber
                  cellindex  = findloc( cellNumbers, cellNumber, 1 ) 
                  if ( cellindex .eq. 0 ) cycle ! Not requested
                  ! Load into flow rates timeseries only if positive 
                  if(sign*this%ArrayBufferDbl(m) .gt. 0.0d0) then
                    flowTimeseries( kcounter, cellindex ) = sign*this%ArrayBufferDbl(m)
                  end if
                end do
              end if
            case(5,6)
              call this%BudgetReader%FillRecordDataBuffer(header, &
                         this%ListItemBuffer, listItemBufferSize, &
                                            spaceAssigned, status )
              if(spaceAssigned .gt. 0) then
                do m = 1, spaceAssigned
                  cellNumber = this%ListItemBuffer(m)%CellNumber
                  ! Determine the index of cellNumber in the list of cells 
                  ! requested for timeseseries
                  cellindex = findloc( cellNumbers, cellNumber, 1 ) 
                  if ( cellindex .eq. 0 ) cycle ! Not requested
                  ! Load into flow rates timeseries only if positive 
                  if(sign*this%ListItemBuffer(m)%BudgetValue .gt. 0.0d0) then
                    flowTimeseries( kcounter, cellindex ) = sign*this%ListItemBuffer(m)%BudgetValue
                  end if
                end do
              end if
            end select

          end if ! found the srcPkgName

        end do ! n = firstRecord, lastRecord

        ! Break if the number of intervals was reached
        if ( kcounter .eq. nTimeIntervals ) exit

      end do ! ktime=kinitial,kfinal


    end subroutine pr_LoadFlowTimeseries



    !! DEPRECATION WARNING !!


    !subroutine pr_SetLayerTypes(this, layerTypes, arraySize)
    !!***************************************************************************************************************
    !!
    !!***************************************************************************************************************
    !! Specifications
    !!---------------------------------------------------------------------------------------------------------------
    !  implicit none
    !  class(FlowModelDataType) :: this
    !  integer,intent(in) :: arraySize
    !  integer,dimension(arraySize),intent(in),target :: layerTypes
    !!---------------------------------------------------------------------------------------------------------------
    !
    !  
    !  if(arraySize .ne. this%Grid%LayerCount) then
    !      write(*,*) "FlowModelDataType: The LayerTypes array size does not match the layer count for the grid. stop"
    !      stop
    !  end if
    !  
    !  this%LayerTypes => layerTypes
    !
    !
    !end subroutine pr_SetLayerTypes






end module FlowModelDataModule
