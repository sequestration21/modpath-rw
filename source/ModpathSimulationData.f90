module ModpathSimulationDataModule
  use ParticleTrackingOptionsModule,only : ParticleTrackingOptionsType
  use ParticleGroupModule,only : ParticleGroupType
  use ModflowRectangularGridModule,only : ModflowRectangularGridType
  use StartingLocationReaderModule,only : ReadAndPrepareLocations, &
                                  CreateMassParticlesAsInternalArray
  implicit none
  
! Set default access status to private
  private
  
! Public derived data type definitions
!--------------------------------------
! type: 
!--------------------------------------
  type,public :: ModpathSimulationDataType
    character(len=200) :: NameFile
    character(len=200) :: ListingFile
    integer :: TraceMode, TraceGroup, TraceID
    integer :: SimulationType
    integer :: TrackingDirection
    integer :: WeakSinkOption
    integer :: WeakSourceOption
    integer :: ReferenceTimeOption
    integer :: StoppingTimeOption
    integer :: BudgetOutputOption
    integer :: TimeseriesOutputOption
    integer :: PathlineFormatOption
    integer :: ZoneDataOption
    integer :: RetardationFactorOption
    integer :: AdvectiveObservationsOption
    integer :: TimePointOption
    integer :: ParticleGroupCount
    integer :: TotalParticleCount
    integer :: TimePointCount
    integer :: StopZone
    integer :: BudgetCellsCount
    doubleprecision :: StopTime
    doubleprecision :: ReferenceTime
    doubleprecision :: TimePointInterval
    character(len=200) :: EndpointFile
    character(len=200) :: PathlineFile
    character(len=200) :: TimeseriesFile
    character(len=200) :: TraceFile
    character(len=200) :: AdvectiveObservationsFile
    character(len=200) :: DispersionFile          ! RWPT
    logical            :: anyObservation =.false. ! RWPT
    integer            :: ParticlesMassOption     ! RWPT
    integer            :: SolutesOption           ! RWPT
    logical            :: shouldUpdateDispersion = .false.  ! RWPT
    integer,dimension(:),allocatable :: BudgetCells
    integer,dimension(:),allocatable :: Zones
    doubleprecision,dimension(:),allocatable :: Retardation
    integer,dimension(:),allocatable         :: ICBound     ! RWPT
    doubleprecision,dimension(:),allocatable :: TimePoints
    type(ParticleGroupType),dimension(:),allocatable :: ParticleGroups
    type(ParticleTrackingOptionsType),allocatable :: TrackingOptions
    logical :: isUniformPorosity =.false.       ! RWPT
    logical :: isUniformRetardation = .false.   ! RWPT
    doubleprecision :: uniformPorosity = 1d0    ! RWPT
    doubleprecision :: uniformRetardation = 1d0 ! RWPT
  contains
    procedure :: ReadFileHeaders=>pr_ReadFileHeaders
    procedure :: ReadData=>pr_ReadData
    procedure :: ReadGPKDEData=>pr_ReadGPKDEData   ! RWPT
    procedure :: ReadOBSData=>pr_ReadOBSData       ! RWPT
    procedure :: ReadRWOPTSData=>pr_ReadRWOPTSData ! RWPT
    procedure :: ReadICData=>pr_ReadICData         ! RWPT
    procedure :: ReadBCData=>pr_ReadBCData         ! RWPT
    procedure :: SetUniformPorosity=>pr_SetUniformPorosity ! RWPT
  end type


contains


  subroutine pr_ReadFileHeaders(this, inUnit)
    use UTL8MODULE,only : u8rdcom
    !--------------------------------------------------------------
    ! Specifications
    !--------------------------------------------------------------
    implicit none
    class(ModpathSimulationDataType) :: this
    integer,intent(in) :: inUnit
    integer :: outUnit, errorCode
    character(len=200) line
    !--------------------------------------------------------------
  
    outUnit = 0
    call u8rdcom(inUnit, outUnit, line, errorCode)
    
    ! Assign the name file
    this%NameFile = line
    
    ! Read MODPATH listing file filename
    read(inUnit, '(a)') this%ListingFile
  
  end subroutine pr_ReadFileHeaders


  ! Inform simulationData about uniform porosity
  subroutine pr_SetUniformPorosity(this, basicData)
    use ModpathBasicDataModule,only : ModpathBasicDataType
    !--------------------------------------------------------------
    ! Specifications
    !--------------------------------------------------------------
    implicit none
    class(ModpathSimulationDataType) :: this
    type(ModpathBasicDataType),intent(in) :: basicData
    !--------------------------------------------------------------
 
    this%isUniformPorosity = basicData%isUniformPorosity
    if ( this%isUniformPorosity ) then 
      ! Needs something to handle the case were ibound(1) != 0 ?
      this%uniformPorosity = basicData%Porosity(1)
    end if
 

  end subroutine pr_SetUniformPorosity


  ! Read simulation data 
  subroutine pr_ReadData(this, inUnit, outUnit, ibound, timeDiscretization, grid)
    use UTL8MODULE,only : urword, ustop, u1dint, u1drel, u1ddbl, u8rdcom, &
                          u3ddblmpusg, u3dintmp, u3dintmpusg, u3ddblmp, ugetnode
    use TimeDiscretizationDataModule,only : TimeDiscretizationDataType
    !--------------------------------------------------------------
    ! Specifications
    !--------------------------------------------------------------
    implicit none
    class(ModpathSimulationDataType), target :: this
    class(ModflowRectangularGridType),intent(in) :: grid
    integer,intent(in) :: inUnit, outUnit
    integer,dimension(:),allocatable :: cellsPerLayer
    integer,dimension(grid%CellCount),intent(in) :: ibound
    type(TimeDiscretizationDataType),intent(in) :: timeDiscretization
    integer :: icol, istart, istop, n, nc, kper, kstp, seqNumber, particleCount, nn, slocUnit, errorCode
    integer :: releaseOption, releaseTimeCount
    doubleprecision :: initialReleaseTime, releaseInterval
    doubleprecision,dimension(:),allocatable :: releaseTimes
    doubleprecision :: frac, r, tinc
    character*24 aname(2)
    character(len=200) line
    DATA aname(1) /'              ZONE ARRAY'/
    DATA aname(2) /'                 RFACTOR'/
    !---------------------------------------------

    ! Deallocate arrays
    if(allocated(this%Zones)) deallocate(this%Zones)
    if(allocated(this%Retardation)) deallocate(this%Retardation)
    if(allocated(this%TimePoints)) deallocate(this%TimePoints)
    if(allocated(this%ParticleGroups)) deallocate(this%ParticleGroups)
    if(allocated(this%TrackingOptions)) deallocate(this%TrackingOptions)
    allocate(this%Zones(grid%CellCount))
    allocate(this%Retardation(grid%CellCount))
    allocate(cellsPerLayer(grid%LayerCount))
    do n = 1, grid%LayerCount
        cellsPerLayer(n) = grid%GetLayerCellCount(n)
    end do
    ! Allocate TrackingOptions
    allocate(this%TrackingOptions)
    
    ! Write header to the listing file
    write(outUnit, *)
    write(outUnit, '(1x,a)') 'MODPATH-RW simulation file data'
    write(outUnit, '(1x,a)') '-------------------------------'
    
    ! Rewind simulation file, then re-read comment lines and the first two non-comment
    ! lines containing the name file and listing file names that were read previously.
    rewind(inUnit)
    call u8rdcom(inUnit, outUnit, line, errorCode)
    read(inUnit, '(a)') line
    
    ! Read simulation options line, then parse line using subroutine urword
    read(inUnit, '(a)') line
    
    ! Simulation type
    icol = 1
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%SimulationType = n
    
    ! Tracking direction
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%TrackingDirection = n
    
    ! Weak sink option
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%WeakSinkOption = n
    
    ! Weak source option
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%WeakSourceOption = n
    
    ! Budget output option
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%BudgetOutputOption = n
    
    ! Trace mode
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%TraceMode = n

    ! Timeseries output option
    ! 0: Original behavior, timeseries records for active particles
    ! 1: Timeseries records for all particles
    ! 2: No timeseries records for any particle ! RWPT
    call urword(line, icol, istart, istop, 2, n, r, -1, 0)
    ! If error while reading the last option (could be triggered by # comments ) 
    if ( line(len(line):len(line)).eq.'E' ) then
      ! Continue as zero
      this%TimeseriesOutputOption = 0
    else
      ! Read from input
      if (istart.eq.len(line)) then
        this%TimeseriesOutputOption = 0
      else
        this%TimeseriesOutputOption = n
      end if
    end if

    ! Particles mass option
    call urword(line, icol, istart, istop, 2, n, r, -1, 0)
    ! If error while reading the last option (could be triggered by # comments ) 
    if ( line(len(line):len(line)).eq.'E' ) then
      ! Continue as zero
      this%ParticlesMassOption = 0
    else
      ! Read from input
      if (istart.eq.len(line)) then
        this%ParticlesMassOption = 0
      else
        this%ParticlesMassOption = n
      end if
    end if

    ! Solutes option
    call urword(line, icol, istart, istop, 2, n, r, -1, 0)
    ! If error while reading the last option (could be triggered by # comments ) 
    if ( line(len(line):len(line)).eq.'E' ) then
      ! Continue as zero
      this%SolutesOption = 0
    else
      ! Read from input
      if (istart.eq.len(line)) then
        this%SolutesOption = 0
      else
        this%SolutesOption = n
      end if
    end if


    ! Pathline format option (hardwire value 1 = consolidate)
    this%PathlineFormatOption = 1
    
    ! Advective observations option (hardwire value 1 = do not use advective observations)
    this%AdvectiveObservationsOption = 1
    
    ! Read coordinate output file names based on simulation type
    select case (this%SimulationType)
      case (1)
        write(outUnit,'(A,I2,A)') 'Endpoint Analysis (Simulation type =',this%SimulationType,')'
        read(inUnit,'(a)') this%EndpointFile
        icol=1
        call urword(this%EndpointFile, icol, istart, istop, 0, n, r, 0, 0)
        this%Endpointfile=this%EndpointFile(istart:istop)
      case (2)
        write(outUnit,'(A,I2,A)') 'Pathline Analysis (Simulation type =', this%SimulationType, ')'
        read(inUnit, '(a)') this%EndpointFile
        icol = 1
        call urword(this%EndpointFile,icol,istart,istop,0,n,r,0,0)
        this%EndpointFile = this%EndpointFile(istart:istop)
        read(inUnit, '(a)') this%PathlineFile
        icol = 1
        call urword(this%PathlineFile, icol, istart, istop, 0, n, r, 0, 0)
        this%PathlineFile = this%PathlineFile(istart:istop)
      case (3)
        write(outUnit,'(A,I2,A)') 'Timeseries Analysis (Simulation type =',this%SimulationType,')'
        read(inUnit, '(a)') this%EndpointFile
        icol=1
        call urword(this%EndpointFile, icol, istart, istop, 0, n, r, 0, 0)
        this%Endpointfile=this%EndpointFile(istart:istop)
        read(inUnit, '(a)') this%TimeseriesFile
        icol = 1
        call urword(this%TimeseriesFile, icol, istart, istop, 0, n, r, 0, 0)
        this%TimeseriesFile = this%TimeseriesFile(istart:istop)
        if(this%AdvectiveObservationsOption.eq.2) then
          read(inUnit, '(a)') this%AdvectiveObservationsFile
          icol = 1
          call urword(this%AdvectiveObservationsFile, icol, istart, istop, 0, n, r,0,0)
          this%AdvectiveObservationsFile = this%AdvectiveObservationsFile(istart:istop)
        end if
      case (4)
        write(outUnit,'(A,I2,A)') 'Combined Pathline and Timeseries Analysis (Simulation type =', this%SimulationType, ')'
        read(inUnit, '(a)') this%EndpointFile
        icol = 1
        call urword(this%EndpointFile,icol,istart,istop,0,n,r,0,0)
        this%EndpointFile = this%EndpointFile(istart:istop)
        read(inUnit, '(a)') this%PathlineFile
        icol = 1
        call urword(this%PathlineFile, icol, istart, istop, 0, n, r, 0, 0)
        this%PathlineFile = this%PathlineFile(istart:istop)
        read(inUnit, '(a)') this%TimeseriesFile
        icol = 1
        call urword(this%TimeseriesFile, icol, istart, istop, 0, n, r, 0, 0)
        this%TimeseriesFile = this%TimeseriesFile(istart:istop)
        if(this%AdvectiveObservationsOption.eq.2) then
          read(inUnit, '(a)') this%AdvectiveObservationsFile
          icol = 1
          call urword(this%AdvectiveObservationsFile, icol, istart, istop, 0, n, r,0,0)
          this%AdvectiveObservationsFile = this%AdvectiveObservationsFile(istart:istop)
        end if
      ! RWPT
      case(5)
        write(outUnit,'(A,I2,A)') 'RWPT with Timeseries Analysis (Simulation type =', this%SimulationType, ')'
        read(inUnit, '(a)') this%EndpointFile
        icol = 1
        call urword(this%EndpointFile,icol,istart,istop,0,n,r,0,0)
        this%EndpointFile = this%EndpointFile(istart:istop)
        read(inUnit, '(a)') this%TimeseriesFile
        icol = 1
        call urword(this%TimeseriesFile, icol, istart, istop, 0, n, r, 0, 0)
        this%TimeseriesFile = this%TimeseriesFile(istart:istop)
        if(this%AdvectiveObservationsOption.eq.2) then
          read(inUnit, '(a)') this%AdvectiveObservationsFile
          icol = 1
          call urword(this%AdvectiveObservationsFile, icol, istart, istop, 0, n, r,0,0)
          this%AdvectiveObservationsFile = this%AdvectiveObservationsFile(istart:istop)
        end if
        this%TrackingOptions%RandomWalkParticleTracking = .true.
      case(6)
        write(outUnit,'(A,I2,A)') 'RWPT with Pathline and Timeseries Analysis (Simulation type =', this%SimulationType, ')'
        read(inUnit, '(a)') this%EndpointFile
        icol = 1
        call urword(this%EndpointFile,icol,istart,istop,0,n,r,0,0)
        this%EndpointFile = this%EndpointFile(istart:istop)
        read(inUnit, '(a)') this%PathlineFile
        icol = 1
        call urword(this%PathlineFile, icol, istart, istop, 0, n, r, 0, 0)
        this%PathlineFile = this%PathlineFile(istart:istop)
        read(inUnit, '(a)') this%TimeseriesFile
        icol = 1
        call urword(this%TimeseriesFile, icol, istart, istop, 0, n, r, 0, 0)
        this%TimeseriesFile = this%TimeseriesFile(istart:istop)
        if(this%AdvectiveObservationsOption.eq.2) then
          read(inUnit, '(a)') this%AdvectiveObservationsFile
          icol = 1
          call urword(this%AdvectiveObservationsFile, icol, istart, istop, 0, n, r,0,0)
          this%AdvectiveObservationsFile = this%AdvectiveObservationsFile(istart:istop)
        end if
        this%TrackingOptions%RandomWalkParticleTracking = .true.
      case(7)
        write(outUnit,'(A,I2,A)') 'RWPT Endpoint Analysis (Simulation type =', this%SimulationType, ')'
        read(inUnit, '(a)') this%EndpointFile
        icol = 1
        call urword(this%EndpointFile,icol,istart,istop,0,n,r,0,0)
        this%EndpointFile = this%EndpointFile(istart:istop)
        this%TrackingOptions%RandomWalkParticleTracking = .true.
      case default
        call ustop('Invalid simulation type. Stop.')
    end select
    
    ! Read trace mode filename if trace mode is on
    if(this%TraceMode .gt. 0) then
      read(inUnit,'(a)') this%TraceFile
      icol=1
      call urword(this%EndpointFile, icol, istart, istop, 0, n, r, 0, 0)
      this%TraceFile=this%TraceFile(istart:istop)
      read(inUnit,*) this%TraceGroup, this%TraceID
    end if
    
    ! Read budget cells
    read(inUnit, *) this%BudgetCellsCount
    if(allocated(this%BudgetCells)) then
        deallocate(this%BudgetCells)
    end if
    allocate(this%BudgetCells(this%BudgetCellsCount))
    if(this%BudgetCellsCount .gt. 0) then
      read(inUnit, *) (this%BudgetCells(n), n = 1, this%BudgetCellsCount)
    end if
 
    ! RWPT 
    ! Only allow forward tracking for RWPT simulations
    if ((( this%SimulationType .eq. 5 ) .or.  &
         ( this%SimulationType .eq. 6 ) .or.  & 
         ( this%SimulationType .eq. 7 )    )  &
      .and. ( this%TrackingDirection .eq. 2 ) ) then 
      call ustop('Random Walk Particle Tracking only accepts Forward tracking. Stop.')
    end if

    ! Tracking direction
    select case(this%TrackingDirection)
      case(1)
        write(outUnit,'(A,I2,A)') 'Forward tracking (Tracking direction = ', this%TrackingDirection,')'
      case(2)
        write(outUnit,'(A,I2,A)') 'Backward tracking (Tracking direction =', this%TrackingDirection,')'
      case default
        call ustop('Invalid tracking direction code. Stop.')
    end select
    
    ! Weak sink option
    select case(this%WeakSinkOption)
      case (1)
        write(outUnit, '(A)') 'Let particles pass through weak sink cells (Weak sink option = 1)'
      case (2)
        write(outUnit,'(A)') 'Stop particles when they enter weak sink cells. (Weak sink option = 2)'
      case default
        call ustop('Invalid weak sink option.')
    end select

    ! Weak source option   
    select case(this%WeakSourceOption)
      case(1)
      write(outUnit,'(A)') 'Let particles pass through weak source cells for backtracking simulations (Weak source option = 1)'
      case(2)
      write(outUnit,'(A)') 'Stop particles when they enter weak source cells for backtracking simulations (Weak source option = 2)'
      case default
      call ustop('Invalid weak source option.')
    end select

    ! Timeseries output option
    select case(this%TimeseriesOutputOption)
      case (0)
        write(outUnit, '(A)') 'Timeseries output for active particles only (Timeseries output option = 0)'
      case (1)
        write(outUnit,'(A)') 'Timeseries output for all particles (Timeseries output option = 1)'
      case (2)
        write(outUnit,'(A)') 'No timeseries output, skip TimeseriesWriter (Timeseries output option = 2)'
      case default
        call ustop('Invalid timeseries output option.')
    end select

    ! Particles mass option
    select case(this%ParticlesMassOption)
      case (0)
        write(outUnit, '(A)') 'Particle groups with default mass and soluteid (ParticlesMassOption = 0)'
      case (1)
        write(outUnit,'(A)') 'Particle groups will read mass (ParticlesMassOption = 1)'
      case (2)
        write(outUnit,'(A)') 'Particle groups will read both mass and soluteid (ParticlesMassOption = 2)'
      case default
        call ustop('Invalid particles mass option.')
    end select
 
    ! Solutes dispersion option
    select case(this%SolutesOption)
      case (0)
        write(outUnit, '(A)') 'Solutes with the same dispersion (SolutesOption= 0)'
      case (1)
        write(outUnit,'(A)') 'Solutes with specific dispersion (SolutesOption = 1)'
      case default
        call ustop('Invalid solutes option.')
    end select


    ! Reference time option
    read(inUnit, '(a)') line
    icol = 1
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%ReferenceTimeOption = n
  
    select case(this%ReferenceTimeOption)
      case(1)
        read(inUnit,*) this%ReferenceTime
        write(outUnit,'(A,E15.7)') 'Reference time = ', this%ReferenceTime
      case(2)
        read(inUnit, *) kper, kstp, frac
        this%ReferenceTime = timeDiscretization%GetTimeFromPeriodAndStep(kper, kstp, frac)
        write(outUnit,'(A,I6,A,I6)') 'Reference time will be calculated for: Period ', KPER,' Step ', KSTP
        write(outUnit,'(A,F10.7)') 'The relative time position within the time step is =',FRAC
        write(outUnit,'(A,E15.7)') 'Computed reference time = ', this%ReferenceTime
      case default
        call ustop('Invalid reference time option.')
    end select

    ! Read stopping option
    this%StopTime = 1.0E+30
    read(inUnit, '(a)') line
    icol = 1
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%StoppingTimeOption = n
    select case(this%StoppingTimeOption)
      case(1)
        write(outUnit,'(A,I2,A)')                                           &
          'Stop tracking at the beginning or end of the MODFLOW simulation (Stopping time option = ',  &
          this%StoppingTimeOption,')'
      case(2)
        write(outUnit,'(A,I2,A)')                                           &
          'Extend initial or final steady-state time step and continue tracking (Stopping time option = ', &
          this%StoppingTimeOption,')'
      case(3)
        write(outUnit,'(A,I2,A)')                                           &
          'Specify a limit for tracking time (Stoping time option = ',this%StoppingTimeOption,')'
        read(inUnit, *) this%StopTime
        write(outUnit,'(A,E15.7)') 'Stop time = ', this%StopTime
      case default
        call ustop('Invalid stop time code. Stop.')
    end select
  
    ! RWPT
    ! Time point data
    if((this%SimulationType .eq. 3) .or. (this%SimulationType .eq. 4) .or.  &
      (this%SimulationType .eq. 5) .or. (this%SimulationType .eq. 6)) then
      read(inUnit, *) this%TimePointOption
      if(this%TimePointOption .eq. 1) then
        read(inUnit, *) this%TimePointCount, this%TimePointInterval
        allocate(this%TimePoints(this%TimePointCount))
        if(this%TimePointCount .gt. 0) then
          this%TimePoints(1) = this%TimePointInterval
          do n = 2, this%TimePointCount
            this%TimePoints(n) = this%TimePoints(n-1) + this%TimePointInterval
          end do   
        end if
      else if(this%TimePointOption .eq. 2) then
        read(inUnit, *) this%TimePointCount
        allocate(this%TimePoints(this%TimePointCount))
        if(this%TimePointCount .gt. 0) then
          read(inUnit, *) (this%TimePoints(n), n = 1, this%TimePointCount)
        end if
      else
          ! write an error message and stop
      end if
    else
      this%TimePointOption = 0
      this%TimePointCount = 0
      this%TimePointInterval = 0.0d0
      allocate(this%TimePoints(0))      
    end if
  
    ! Zone array
    read(inUnit, '(a)') line
    icol = 1
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%ZoneDataOption = n
    if(this%ZoneDataOption .gt. 1) then
      write(outUnit, '(/a)') 'A zone array will be read.'
      read(inUnit,*) this%StopZone
      if(this%StopZone .lt. 1) then
        write(outUnit,'(A,I5)')                                               &
          'Particles will be allowed to pass through all zones. StopZone = ', this%StopZone
      else
        write(outUnit,'(A,I5)')                                               &
          'Particles will be terminated when they enter cells with a zone numbers equal to ', this%StopZone
      end if
      if((grid%GridType .eq. 1) .or. (grid%GridType .eq. 3)) then
        call u3dintmp(inUnit, outUnit, grid%LayerCount, grid%RowCount,      &
          grid%ColumnCount, grid%CellCount, this%Zones, ANAME(1))            
      else if((grid%GridType .eq. 2) .or. (grid%GridType .eq. 4)) then
        call u3dintmpusg(inUnit, outUnit, grid%CellCount, grid%LayerCount, this%Zones,&
          ANAME(1), cellsPerLayer)
      else
        write(outUnit,*) 'Invalid grid type specified when reading zone array data.'
        write(outUnit,*) 'Stopping.'
        call ustop(' ')
      end if
    else
      write(outUnit,'(A)') 'The zone value for all cells = 1'
      this%StopZone = 0
      do n = 1, grid%CellCount
          this%Zones(n) = 1
      end do
    end if
      
    ! Retardation array
    read(inUnit, '(a)') line
    icol = 1
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    this%RetardationFactorOption = n  
    if(this%RetardationFactorOption .gt. 1) then
      write(outUnit,'(/A)') 'The retardation factor array will be read.'
      if((grid%GridType .eq. 1) .or. (grid%GridType .eq. 3)) then
        call u3ddblmp(inUnit, outUnit, grid%LayerCount, grid%RowCount,     &
          grid%ColumnCount, grid%CellCount, this%Retardation, aname(2)) 
      else if((grid%GridType .eq. 2) .or. (grid%GridType .eq. 4)) then
        call u3ddblmpusg(inUnit, outUnit, grid%CellCount, grid%LayerCount, &
          this%Retardation, aname(2), cellsPerLayer)
      else
        write(outUnit,*) 'Invalid grid type specified when reading retardation array data.'
        write(outUnit,*) 'Stopping.'
        call ustop(' ')            
      end if
      ! RWPT
      ! Check if all cells have the same retardation factor
      if (all(this%Retardation.eq.this%Retardation(1))) then
          this%isUniformRetardation = .true.
          this%uniformRetardation = this%Retardation(1) 
      end if
    else
      write(outUnit,'(/A)') 'The retardation factor for all cells = 1'
      do n = 1, grid%CellCount
        this%Retardation(n) = 1.0d0
      end do
      this%isUniformRetardation = .true.
    end if
      
    ! Particle data
    read(inUnit, *) this%ParticleGroupCount
    write(outUnit,'(/A,I5)') 'Number of particle groups = ', this%ParticleGroupCount
  
    seqNumber = 0
    this%TotalParticleCount = 0
    particleCount = 0
    if(this%ParticleGroupCount .gt. 0) then
      allocate(this%ParticleGroups(this%ParticleGroupCount))
      do n = 1, this%ParticleGroupCount
        this%ParticleGroups(n)%Group = n
        read(inUnit, '(a)') this%ParticleGroups(n)%Name
        read(inUnit, *) releaseOption
        
        select case (releaseOption)
          case (1)
            read(inUnit, *) initialReleaseTime
            call this%ParticleGroups(n)%SetReleaseOption1(initialReleaseTime)
          case (2)
            read(inUnit, *) releaseTimeCount, initialReleaseTime, releaseInterval
            call this%ParticleGroups(n)%SetReleaseOption2(initialReleaseTime, &
              releaseTimeCount, releaseInterval)
          case (3)
            read(inUnit, *) releaseTimeCount
            if(allocated(releaseTimes)) deallocate(releaseTimes)
            allocate(releaseTimes(releaseTimeCount))
            read(inUnit, *) (releaseTimes(nn), nn = 1, releaseTimeCount)
            call this%ParticleGroups(n)%SetReleaseOption3(releaseTimeCount,   &
              releaseTimes)
          case default
            ! write error message and stop
        end select
      
        read(inUnit, '(a)') line
        icol = 1
        call urword(line,icol,istart,istop,1,n,r,0,0)
        if(line(istart:istop) .eq. 'EXTERNAL') then
          call urword(line,icol,istart,istop,0,n,r,0,0)
          this%ParticleGroups(n)%LocationFile = line(istart:istop)
          slocUnit = 0
        else if(line(istart:istop) .eq. 'INTERNAL') then
          this%ParticleGroups(n)%LocationFile = ''
          slocUnit = inUnit
        else
          call ustop('Invalid starting locations file name. stop.')
        end if
        call ReadAndPrepareLocations(slocUnit, outUnit, this%ParticleGroups(n),   &
          ibound, grid%CellCount, grid, seqNumber)
        write(outUnit, '(a,i4,a,i10,a)') 'Particle group ', n, ' contains ',      &
          this%ParticleGroups(n)%TotalParticleCount, ' particles.'
        particleCount = particleCount + this%ParticleGroups(n)%TotalParticleCount

        ! RWPT
        if ( this%ParticlesMassOption .ge. 1 ) then 
          ! Read group mass, is a proxy for concentrations
          ! when mass is uniform for a pgroup
          read(inUnit, *) this%ParticleGroups(n)%Mass
          this%ParticleGroups(n)%Particles(:)%Mass = this%ParticleGroups(n)%Mass
          ! Read the solute id for this group 
          if ( this%ParticlesMassOption .eq. 2 ) then 
            read(inUnit, *) this%ParticleGroups(n)%Solute
          end if
        end if

      end do

      this%TotalParticleCount = particleCount
      write(outUnit, '(a,i10)') 'Total number of particles = ', this%TotalParticleCount
      write(outUnit, *)
    end if

    ! TrackingOptions data
    !allocate(this%TrackingOptions) ! Moved up 
    ! Initialize defaults
    this%TrackingOptions%DebugMode = .false.
    this%TrackingOptions%BackwardTracking = .false.
    this%TrackingOptions%CreateTrackingLog = .false.
    this%TrackingOptions%StopAtWeakSinks = .false.
    this%TrackingOptions%StopAtWeakSources = .false.
    this%TrackingOptions%ExtendSteadyState = .true.
    this%TrackingOptions%SpecifyStoppingTime = .false.
    this%TrackingOptions%SpecifyStoppingZone = .false.
    this%TrackingOptions%StopTime = this%StopTime
    this%TrackingOptions%StopZone = this%StopZone
    ! Set specific option values
    if(this%TrackingDirection .eq. 2) this%TrackingOptions%BackwardTracking = .true.
    if(this%WeakSinkOption .eq. 2) this%TrackingOptions%StopAtWeakSinks = .true.
    if(this%WeakSourceOption .eq. 2) this%TrackingOptions%StopAtWeakSources = .true.
    if(this%StoppingTimeOption .ne. 2) this%TrackingOptions%ExtendSteadyState = .false.
    if(this%StoppingTimeOption .eq. 3) this%TrackingOptions%SpecifyStoppingTime = .true.
    if(this%ZoneDataOption .eq. 1) this%TrackingOptions%SpecifyStoppingZone = .true. 
    if(this%TimeseriesOutputOption .eq. 2) this%TrackingOptions%skipTimeseriesWriter = .true.

    ! Set flag to indicate whether dispersion 
    ! should be updated for different particles or not.
    ! It should be done only if SolutesOption indicates 
    ! multidispersion and simulation is RWPT. 
    if ( & 
      ( this%SolutesOption .eq. 1 ) .and. & 
      ( this%TrackingOptions%RandomWalkParticleTracking ) ) then 
      this%shouldUpdateDispersion = .true.
    end if 


  end subroutine pr_ReadData


  ! Read specific GPKDE data
  subroutine pr_ReadGPKDEData( this, gpkdeFile, gpkdeUnit, outUnit )
    use UTL8MODULE,only : urword, ustop
    !--------------------------------------------------------------
    ! Specifications
    !--------------------------------------------------------------
    implicit none
    ! input 
    class(ModpathSimulationDataType), target :: this
    character(len=200), intent(in)           :: gpkdeFile
    integer, intent(in)                      :: gpkdeUnit
    integer, intent(in)                      :: outUnit
    ! local
    integer :: isThisFileOpen = -1
    integer :: icol,istart,istop,n
    doubleprecision    :: r
    character(len=200) :: line
    !--------------------------------------------------------------

    write(outUnit, *)
    write(outUnit, '(1x,a)') 'MODPATH-RW GPKDE file data'
    write(outUnit, '(1x,a)') '--------------------------'

    ! Verify if GPKDE unit is open 
    inquire( file=gpkdeFile, number=isThisFileOpen )
    if ( isThisFileOpen .lt. 0 ) then 
      ! No gpkde 
      write(outUnit,'(A)') 'GPKDE reconstruction is disabled'
      return
    end if

    ! Yes gpkde 
    ! Requires a timeseries simulation
    if ( &
      (this%SimulationType .eq. 3) .or. (this%SimulationType .eq. 4) .or. &
      (this%SimulationType .eq. 5) .or. (this%SimulationType .eq. 6) ) then

      write(outUnit,'(A)') 'GPKDE reconstruction is enabled'
      this%TrackingOptions%GPKDEReconstruction = .true.
    
      ! Read gpkde output file
      read(gpkdeUnit, '(a)') this%TrackingOptions%gpkdeOutputFile
      icol = 1
      call urword(this%TrackingOptions%gpkdeOutputFile,icol,istart,istop,0,n,r,0,0)
      this%TrackingOptions%gpkdeOutputFile = this%TrackingOptions%gpkdeOutputFile(istart:istop)
    
      ! Read domainOrigin
      read(gpkdeUnit, '(a)') line
      icol = 1
      call urword(line, icol, istart, istop, 3, n, r, 0, 0)
      this%TrackingOptions%gpkdeDomainOrigin(1) = r
      call urword(line, icol, istart, istop, 3, n, r, 0, 0)
      this%TrackingOptions%gpkdeDomainOrigin(2) = r
      call urword(line, icol, istart, istop, 3, n, r, 0, 0)
      this%TrackingOptions%gpkdeDomainOrigin(3) = r
    
      ! Read domainSize
      read(gpkdeUnit, '(a)') line
      icol = 1
      call urword(line, icol, istart, istop, 3, n, r, 0, 0)
      this%TrackingOptions%gpkdeDomainSize(1) = r
      call urword(line, icol, istart, istop, 3, n, r, 0, 0)
      this%TrackingOptions%gpkdeDomainSize(2) = r
      call urword(line, icol, istart, istop, 3, n, r, 0, 0)
      this%TrackingOptions%gpkdeDomainSize(3) = r
    
      ! Read binSize
      read(gpkdeUnit, '(a)') line
      icol = 1
      call urword(line, icol, istart, istop, 3, n, r, 0, 0)
      this%TrackingOptions%gpkdeBinSize(1) = r
      call urword(line, icol, istart, istop, 3, n, r, 0, 0)
      this%TrackingOptions%gpkdeBinSize(2) = r
      call urword(line, icol, istart, istop, 3, n, r, 0, 0)
      this%TrackingOptions%gpkdeBinSize(3) = r
     
      ! Health control
      if ( any(this%TrackingOptions%gpkdeBinSize.lt.0d0) ) then 
        write(outUnit,'(A)') 'One of the GPKDE binSizes is negative. They should be positive.'
        call ustop('One of the GPKDE binSizes is negative. They should be positive. Stop.')
      end if 

      ! Set binVolume, cannot be zero
      this%TrackingOptions%gpkdeBinVolume = product(&
          this%TrackingOptions%gpkdeBinSize, mask=this%TrackingOptions%gpkdeBinSize.ne.0d0)

      ! Read nOptimizationLoops
      read(gpkdeUnit, '(a)') line
      icol = 1
      call urword(line, icol, istart, istop, 2, n, r, 0, 0)
      this%TrackingOptions%gpkdeNOptLoops = n
    
      ! Read reconstruction method
      ! 0: without kernel database, brute force
      ! 1: with kernel database and read parameters
      read(gpkdeUnit, '(a)') line
      icol = 1
      call urword(line, icol, istart, istop, 2, n, r, 0, 0)
      if (n.eq.0) then 
        this%TrackingOptions%gpkdeKernelDatabase = .false.
      else
        this%TrackingOptions%gpkdeKernelDatabase = .true.
      end if
    
      if ( this%TrackingOptions%gpkdeKernelDatabase ) then 
        write(outUnit,'(A)') 'GPKDE reconstruction with kernel database'
        ! Read kernel database params
        ! - min   h/lambda
        ! - delta h/lambda
        ! - max   h/lambda
        read(gpkdeUnit, '(a)') line
        icol = 1
        call urword(line, icol, istart, istop, 3, n, r, 0, 0)
        this%TrackingOptions%gpkdeKDBParams(1) = r
        call urword(line, icol, istart, istop, 3, n, r, 0, 0)
        this%TrackingOptions%gpkdeKDBParams(2) = r
        call urword(line, icol, istart, istop, 3, n, r, 0, 0)
        this%TrackingOptions%gpkdeKDBParams(3) = r
      else
        write(outUnit,'(A)') 'GPKDE reconstruction with brute force, no kernel database'
        this%TrackingOptions%gpkdeKernelDatabase = .false.
        ! Read kernel params
        ! - min   h/lambda
        ! - max   h/lambda
        read(gpkdeUnit, '(a)') line
        icol = 1
        call urword(line, icol, istart, istop, 3, n, r, 0, 0)
        this%TrackingOptions%gpkdeKDBParams(1) = r
        this%TrackingOptions%gpkdeKDBParams(2) = 0d0 ! NOT USED
        call urword(line, icol, istart, istop, 3, n, r, 0, 0)
        this%TrackingOptions%gpkdeKDBParams(3) = r
      end if 
    
      ! Read kind of reconstruction output
      ! 0: as total mass density. Smoothed phi*R*c_r
      ! 1: as resident concentration
      read(gpkdeUnit, '(a)') line
      icol = 1
      call urword(line, icol, istart, istop, 2, n, r, 0, 0)
      if (n.eq.0) then 
        write(outUnit,'(A)') 'GPKDE output is expressed as smoothed total mass density.'
        this%TrackingOptions%gpkdeAsConcentration = .false.
      else
        ! If requested as resident concentration, 
        ! verifies whether porosities and retardation 
        ! are spatially uniform.
        write(outUnit,'(A)') 'GPKDE output is requested to be expressed as resident concentration.'
        if ( this%isUniformPorosity .and. this%isUniformRetardation ) then 
          write(outUnit,'(A)') 'Porosity and retardation are spatially uniform, GPKDE output is given as concentration.'
          this%TrackingOptions%gpkdeAsConcentration = .true.
          this%TrackingOptions%gpkdeScalingFactor =&
            1d0/(this%uniformPorosity*this%uniformRetardation*this%TrackingOptions%gpkdeBinVolume)
        else
          write(outUnit,'(A)') 'Porosity and retardation are NOT spatially uniform, GPKDE output is total mass density.'
          this%TrackingOptions%gpkdeScalingFactor =&
            1d0/(this%TrackingOptions%gpkdeBinVolume)
        end if
      end if

    else

      ! If simulation is not timeseries
      write(outUnit,'(A)') 'GPKDE reconstruction requires a timeseries. Will remain disabled.'

    end if

    ! Close gpkde data file
    close( gpkdeUnit )


  end subroutine pr_ReadGPKDEData


  ! Read specific OBS data
  subroutine pr_ReadOBSData( this, obsFile, obsUnit, outUnit, grid )
    use UTL8MODULE,only : urword,ustop,ugetnode,u3dintmp, u3dintmpusg
    use ObservationModule, only: ObservationType
    !--------------------------------------------------------------
    ! Specifications
    !--------------------------------------------------------------
    implicit none
    ! input 
    class(ModpathSimulationDataType), target :: this
    character(len=200), intent(in)           :: obsFile
    integer, intent(in)                      :: obsUnit
    integer, intent(in)                      :: outUnit
    class(ModflowRectangularGridType),intent(in) :: grid
    ! local
    integer :: nObservations  = 0
    character(len=100) :: tempChar
    integer :: layerCount, rowCount, columnCount, cellCount
    type( ObservationType ), pointer :: obs => null()
    integer :: readStyle, no, cellNumber, layer, row, column, ocount
    integer,dimension(:),allocatable :: obsCells
    integer,dimension(:),allocatable :: cellsPerLayer
    integer :: isThisFileOpen = -1
    integer :: icol,istart,istop,n,nc
    integer :: ioInUnit = 0
    doubleprecision    :: r
    character(len=200) :: line
    character(len=24)  :: aname(1)
    DATA aname(1) /'                OBSCELLS'/
    !--------------------------------------------------------------

    write(outUnit, *)
    write(outUnit, '(1x,a)') 'MODPATH-RW OBS file data'
    write(outUnit, '(1x,a)') '--------------------------'

    ! Verify if OBS unit is open 
    inquire( file=obsFile, number=isThisFileOpen )
    if ( isThisFileOpen .lt. 0 ) then 
      ! No obs
      write(outUnit,'(A)') 'No observations were specified'
      return
    end if

    ! OBS unit is open

    ! Read the number of observation cells
    read(obsUnit, *, iostat=ioInUnit) line
    icol = 1
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    if ( n .le. 0 ) then 
      ! No obs
      write(outUnit,'(1X,A,I6,A)') 'Given number of observations: ', n, '. Default to no observations'
    else
      ! ok, initialize
      nObservations = n
      this%anyObservation = .true.
      write(outUnit,'(1X,A,I6)') 'Given number of observations: ', nObservations

      ! Allocate observation arrays
      call this%TrackingOptions%InitializeObservations( nObservations )

      ! It might be needed downstream
      layerCount  = grid%LayerCount
      rowCount    = grid%RowCount
      columnCount = grid%ColumnCount
      cellCount   = grid%CellCount
      
      ! Allocate id arrays in tracking options
      if(allocated(this%TrackingOptions%isObservation)) & 
          deallocate(this%TrackingOptions%isObservation)
      allocate(this%TrackingOptions%isObservation(cellCount))
      if(allocated(this%TrackingOptions%idObservation)) & 
          deallocate(this%TrackingOptions%idObservation)
      allocate(this%TrackingOptions%idObservation(cellCount))
      this%TrackingOptions%isObservation(:) = .false.
      this%TrackingOptions%idObservation(:) = -999

      ! Read observation cells and assign 
      ! proper variables
      do nc = 1, nObservations

        ! A pointer
        obs => this%TrackingOptions%Observations(nc) 

        ! Read observation id
        read(obsUnit, '(a)', iostat=ioInUnit) line
        icol = 1
        call urword(line, icol, istart, istop, 2, n, r, 0, 0)
        obs%id = n 
       
        ! Read observation filename and assign an output unit 
        read(obsUnit, '(a)') obs%outputFileName
        icol = 1
        call urword(obs%outputFileName,icol,istart,istop,0,n,r,0,0)
        obs%outputFileName = obs%outputFileName(istart:istop)
        obs%outputUnit     = 5500 + nc
        obs%auxOutputUnit  = 7700 + nc
        tempChar           = 'temp'
        write( unit=obs%auxOutputFileName, fmt='(a)')&
            trim(adjustl(tempChar))//'_'//trim(adjustl(obs%outputFileName))

        ! Read observation style (sink obs, normal count of particles obs)
        read(obsUnit, '(a)', iostat=ioInUnit) line
        icol = 1
        call urword(line, icol, istart, istop, 2, n, r, 0, 0)
        obs%style = n 

        ! Is the style that requires flow-rates ?
        if ( obs%style .eq. 2 ) then 
          this%TrackingOptions%anySinkObservation = .true.
        end if 

        ! Read observation cell option
        ! Determine how to read cells
        read(obsUnit, '(a)', iostat=ioInUnit) line
        icol = 1
        call urword(line, icol, istart, istop, 2, n, r, 0, 0)
        obs%cellOption = n 

        ! Load observation cells
        select case( obs%cellOption )
          ! In case 1, a list of cell ids is specified, that 
          ! compose the observation.  
          case (1)
            ! Read number of observation cells 
            read(obsUnit, '(a)', iostat=ioInUnit) line
            icol = 1
            call urword(line, icol, istart, istop, 2, n, r, 0, 0)
            obs%nCells = n 
            
            ! Depending on the number of cells 
            ! allocate array for cell ids
            if ( allocated( obs%cells ) ) deallocate( obs%cells )
            allocate( obs%cells(obs%nCells) )
            if ( allocated( obs%nRecordsCell ) ) deallocate( obs%nRecordsCell )
            allocate( obs%nRecordsCell(obs%nCells) )
            obs%nRecordsCell(:) = 0

            ! Are these ids as (lay,row,col) or (cellid) ?
            read(obsUnit, '(a)', iostat=ioInUnit) line
            icol = 1
            call urword(line, icol, istart, istop, 2, n, r, 0, 0)
            readStyle = n

            ! Load the observation cells
            if( readStyle .eq. 1) then
              ! Read as layer, row, column
              do no = 1, obs%nCells
                read(obsUnit, *) layer, row, column
                call ugetnode(layerCount, rowCount, columnCount, layer, row, column,cellNumber)
                obs%cells(no) = cellNumber
              end do 
            else if ( readStyle .eq. 2 ) then 
              do no = 1, obs%nCells
                read(obsUnit,*)  cellNumber
                obs%cells(no) = cellNumber
              end do 
            else
              call ustop('Invalid observation kind. Stop.')
            end if

          case (2)
            ! In case 2, observation cells are given by specifying a 3D array
            ! with 0 (not observation) and 1 (observation) 

            ! Required for u3d
            if(allocated(obsCells)) deallocate(obsCells)
            allocate(obsCells(grid%CellCount))
            obsCells(:) = 0
         
            ! Read cells
            if((grid%GridType .eq. 1) .or. (grid%GridType .eq. 3)) then
              call u3dintmp(obsUnit, outUnit, grid%LayerCount, grid%RowCount,      &
                grid%ColumnCount, grid%CellCount, obsCells, aname(1)) 
            else if((grid%GridType .eq. 2) .or. (grid%GridType .eq. 4)) then
              call u3dintmpusg(obsUnit, outUnit, grid%CellCount, grid%LayerCount,  &
                obsCells, aname(1), cellsPerLayer)
            else
              write(outUnit,*) 'Invalid grid type specified when reading OBSCELLS array data.'
              write(outUnit,*) 'Stopping.'
              call ustop(' ')          
            end if

            ! Count how many obs cells specified 
            obs%nCells = count(obsCells/=0)

            if ( obs%nCells .eq. 0 ) then 
              write(outUnit,*) 'No observation cells in the array of cells for observation:', obs%id
              write(outUnit,*) 'Stopping.'
              call ustop('No observation cells in the array of cells. Stop.')
            end if

            ! Depending on the number of cells 
            ! allocate array for cell ids
            if ( allocated( obs%cells ) ) deallocate( obs%cells )
            allocate( obs%cells(obs%nCells) )
            if ( allocated( obs%nRecordsCell ) ) deallocate( obs%nRecordsCell )
            allocate( obs%nRecordsCell(obs%nCells) )
            obs%nRecordsCell(:) = 0

            ! Fill obs%cells with the corresponding cell numbers
            ocount = 0
            do n =1,grid%CellCount
              if(obsCells(n).eq.0) cycle
              ocount = ocount + 1
              obs%cells(ocount) = n 
            end do

          case default
            ! Invalid option
            call ustop('Invalid observation cells reading option. Stop.')
        end select


        ! Assign into id arrays
        do no =1, obs%nCells
          this%TrackingOptions%isObservation(obs%cells(no)) = .true.
          ! The id on the list of cells !
          this%TrackingOptions%idObservation(obs%cells(no)) = nc
        end do


        ! Read observation cell time option
        ! Determine how to reconstruct timeseries
        read(obsUnit, '(a)', iostat=ioInUnit) line
        icol = 1
        call urword(line, icol, istart, istop, 2, n, r, 0, 0)
        obs%timeOption = n 

        ! Timeoption determine from where 
        ! to obtain the timeseries considered for 
        ! reconstruction
        select case(obs%timeOption)
          case(1)
            ! Get it from the timeseries run 
            ! Is there any gpkde config for this ?
            continue
          case (2)
            ! Create it by reading input 
            ! params like for example the 
            ! number of datapoints

            ! Needs reading

            continue
          case default
            ! Get it from the timeseries run 
            continue
        end select

        ! Depending on parameters, initialize observation file as 
        ! binary or plain-text 

      end do 

      ! Close the OBS unit
      close( obsUnit ) 

    end if  


  end subroutine pr_ReadOBSData



  ! Read specific RWOPTS data
  subroutine pr_ReadRWOPTSData( this, rwoptsFile, rwoptsUnit, outUnit, grid )
    use UTL8MODULE,only : urword,ustop,u3dintmpusg, u3dintmp
    !--------------------------------------------------------------
    ! Specifications
    !--------------------------------------------------------------
    implicit none
    ! input 
    class(ModpathSimulationDataType), target     :: this
    character(len=200), intent(in)               :: rwoptsFile
    integer, intent(in)                          :: rwoptsUnit
    integer, intent(in)                          :: outUnit
    class(ModflowRectangularGridType),intent(in) :: grid
    ! local
    type(ParticleTrackingOptionsType), pointer :: trackingOptions
    integer :: isThisFileOpen = -1
    integer :: icol,istart,istop,n,nd,currentDim,dcount
    doubleprecision    :: r
    character(len=200) :: line
    integer, dimension(:), allocatable :: cellsPerLayer
    character(len=24),dimension(1) :: aname
    data aname(1) /'       ICBOUND'/
    !--------------------------------------------------------------

    write(outUnit, *)
    write(outUnit, '(1x,a)') 'MODPATH-RW RWOPTS file data'
    write(outUnit, '(1x,a)') '---------------------------'

    ! Verify if unit is open 
    inquire( file=rwoptsFile, number=isThisFileOpen )
    if ( isThisFileOpen .lt. 0 ) then 
      ! No rwopts file
      write(outUnit,'(A)') 'RWOPTS were not specified in name file and are required for RW simulation.'
      call ustop('RWOPTS were not specified in name file and are required for RW simulation. Stop.')
    end if

    ! Pointer to this%TrackingOptions
    trackingOptions => this%TrackingOptions

    ! Time Step kind 
    read(rwoptsUnit, '(a)') line
    icol = 1
    call urword(line,icol,istart,istop,1,n,r,0,0)
    line = line(istart:istop)
    ! Advection 
    if ( line .eq. 'ADV' ) then
      trackingOptions%timeStepKind = 1
      read( rwoptsUnit, * ) line
      icol = 1
      call urword(line,icol,istart,istop,3,n,r,0,0)
      trackingOptions%timeStepParameters(1) = r
      write(outUnit,'(A)') 'RW time step will be selected with the ADV criteria.'
    ! Dispersion 
    else if ( line .eq. 'DISP' ) then
      trackingOptions%timeStepKind = 2
      read( rwoptsUnit, * ) line
      icol = 1
      call urword(line,icol,istart,istop,3,n,r,0,0)
      trackingOptions%timeStepParameters(2) = r
      write(outUnit,'(A)') 'RW time step will be selected with the DISP criteria.'
    ! Minimum between advection and dispersion 
    else if ( line .eq. 'MIN_ADV_DISP' ) then
      trackingOptions%timeStepKind = 3
      read( rwoptsUnit, * ) line
      icol = 1
      call urword(line,icol,istart,istop,3,n,r,0,0)
      trackingOptions%timeStepParameters(1) = r
      read( rwoptsUnit, * ) line
      icol = 1
      call urword(line,icol,istart,istop,3,n,r,0,0)
      trackingOptions%timeStepParameters(2) = r
      write(outUnit,'(A)') 'RW time step will be selected with the MIN_ADV_DISP criteria.'
    ! Fixed 
    else if ( line .eq. 'FIXED' ) then
      trackingOptions%timeStepKind = 4
      read( rwoptsUnit, * ) line
      icol = 1
      call urword(line,icol,istart,istop,3,n,r,0,0)
      trackingOptions%timeStepParameters(1) = r
      write(outUnit,'(A)') 'RW time step is given with FIXED criteria.'
    else
      call ustop('Invalid option for time step selection. Stop.')
    end if


    ! Advection Integration Kind
    read(rwoptsUnit, '(a)') line
    icol = 1
    call urword(line,icol,istart,istop,1,n,r,0,0)
    line = line(istart:istop)
    select case(line)
      case('EXPONENTIAL')
        trackingOptions%advectionKind = 1
        write(outUnit,'(A)') 'RW advection integration is EXPONENTIAL.'
      case('EULERIAN')
        trackingOptions%advectionKind = 2
        write(outUnit,'(A)') 'RW advection integration is EULERIAN.'
      case default
        trackingOptions%advectionKind = 2
        write(outUnit,'(A)') 'Given RW advection integration is not valid. Defaults to EULERIAN.'
    end select

    ! Read RW dimensionsmask. Determines to which dimensions apply RW displacements
    read(rwoptsUnit, '(a)') line
    
    ! X
    icol = 1
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    trackingOptions%dimensionMask(1) = n

    ! Y
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    trackingOptions%dimensionMask(2) = n

    ! Z
    call urword(line, icol, istart, istop, 2, n, r, 0, 0)
    trackingOptions%dimensionMask(3) = n

    ! Health check
    if ( any( trackingOptions%dimensionMask.gt.1 ) ) then 
      ! Invalid dimensions
      write(outUnit,'(A)') 'Invalid value for dimensions mask. Should 0 or 1.'
      call ustop('Invalid value for dimensions mask. Should 0 or 1. Stop.')
    end if 
    if ( any( trackingOptions%dimensionMask.lt.0 ) ) then 
      ! Invalid dimensions
      write(outUnit,'(A)') 'Invalid value for dimensions mask. Should 0 or 1.'
      call ustop('Invalid value for dimensions mask. Should 0 or 1. Stop.')
    end if 


    ! Set nDim
    trackingOptions%nDim = sum(trackingOptions%dimensionMask)
    if ( trackingOptions%nDim .le. 0 ) then
      ! No dimensions
      write(outUnit,'(A)') 'No dimensions were given for RW displacements at RWOPTS, nDim .eq. 0.'
      call ustop('No dimensions were given for RW displacements at RWOPTS, nDim .eq. 0. Stop.')
    end if 


    ! Save dim mask into dimensions 
    if ( allocated( trackingOptions%dimensions ) ) deallocate( trackingOptions%dimensions ) 
    allocate( trackingOptions%dimensions( trackingOptions%nDim  ) )
    dcount= 0
    do nd = 1, 3
      if ( trackingOptions%dimensionMask(nd) .eq. 0 ) cycle
      dcount = dcount + 1 
      trackingOptions%dimensions(dcount) = nd
    end do 


    ! Detect idDim and report dimensions
    ! where displacements will be applied
    select case(trackingOptions%nDim)
      ! 1D
      case(1)
        trackingOptions%twoDimensions = .true. ! TEMP
        write(outUnit,'(A)') 'RW displacements for 1 dimension.'
        ! Relate x,y,z dimensions to 1 dimensions
        do nd = 1,3
          if ( trackingOptions%dimensionMask( nd ) .eq. 0 ) cycle
          select case(nd) 
            case (1)
              trackingOptions%idDim1 = nd
              write(outUnit,'(A)') 'RW displacements for X dimension.'
            case (2)
              trackingOptions%idDim1 = nd
              write(outUnit,'(A)') 'RW displacements for Y dimension.'
            case (3)
              trackingOptions%idDim1 = nd
              write(outUnit,'(A)') 'RW displacements for Z dimension.'
          end select   
          ! Use the first found
          exit
        end do
      ! 2D
      case(2)
        trackingOptions%twoDimensions = .true. ! TEMP
        write(outUnit,'(A)') 'RW displacements for 2 dimensions.'
        ! Relate x,y,z dimensions to 1,2 dimensions
        do nd = 1,3
          if ( trackingOptions%dimensionMask( nd ) .eq. 0 ) cycle
          currentDim = sum( trackingOptions%dimensionMask(1:nd) )
          select case(nd) 
            case (1)
              trackingOptions%idDim1 = n
              write(outUnit,'(A)') 'RW displacements for X dimension.'
            case (2)
              if ( currentDim .eq. 1 ) then 
                trackingOptions%idDim1 = nd
              else if ( currentDim .eq. 2 ) then
                trackingOptions%idDim2 = nd
              end if
              write(outUnit,'(A)') 'RW displacements for Y dimension.'
            case (3)
              trackingOptions%idDim2 = nd
              write(outUnit,'(A)') 'RW displacements for Z dimension.'
          end select   
        end do
      ! 3D
      case(3)
        trackingOptions%twoDimensions = .false.! TEMP
        write(outUnit,'(A)') 'RW displacements for 3 dimensions.'
    end select


    ! Close rwopts data file
    close( rwoptsUnit )


  end subroutine pr_ReadRWOPTSData


  ! Read specific IC data
  subroutine pr_ReadICData( this, icFile, icUnit, outUnit, grid, porosity )
    use UTL8MODULE,only : urword,ustop,u3ddblmpusg, u3ddblmp
    !--------------------------------------------------------------
    ! Specifications
    !--------------------------------------------------------------
    implicit none
    ! input 
    class(ModpathSimulationDataType), target     :: this
    character(len=200), intent(in)               :: icFile
    integer, intent(in)                          :: icUnit
    integer, intent(in)                          :: outUnit
    class(ModflowRectangularGridType),intent(in) :: grid
    doubleprecision, dimension(:)                :: porosity
    ! local
    integer :: isThisFileOpen = -1
    integer :: icol,istart,istop,n
    integer :: nc, nic, nd, m
    doubleprecision    :: r
    character(len=200) :: line
    integer :: nInitialConditions, nValidInitialConditions 
    integer :: initialConditionFormat
    integer :: newParticleGroupCount
    integer :: pgCount
    integer :: soluteId
    integer, dimension(:), pointer :: dimensionMask
    integer, pointer               :: nDim
    type(ParticleGroupType),dimension(:),allocatable :: particleGroups
    type(ParticleGroupType),dimension(:),allocatable :: newParticleGroups
    doubleprecision, dimension(:), allocatable :: densityDistribution
    integer, dimension(:), allocatable :: cellsPerLayer
    doubleprecision :: initialReleaseTime
    doubleprecision :: particleMass, effParticleMass
    doubleprecision :: cellTotalMass, totalAccumulatedMass
    doubleprecision :: cellDissolvedMass, totalDissolvedMass
    doubleprecision :: cellVolume,sX,sY,sZ,nPX,nPY,nPZ
    doubleprecision :: nParticlesCell 
    integer :: totalParticleCount, seqNumber, idmax, particleCount
    integer :: iNPX,iNPY,iNPZ,NPCELL
    integer :: validCellCounter, cellCounter
    integer, allocatable, dimension(:,:) :: subDivisions
    character(len=24),dimension(1) :: aname
    data aname(1) /'            IC'/
    !--------------------------------------------------------------

    write(outUnit, *)
    write(outUnit, '(1x,a)') 'MODPATH-RW IC file data'
    write(outUnit, '(1x,a)') '-----------------------'

    ! Verify if unit is open 
    inquire( file=icFile, number=isThisFileOpen )
    if ( isThisFileOpen .lt. 0 ) then 
      ! No ic 
      write(outUnit,'(A)') 'No IC package for the RW simulation was specified.'
      return
    end if

    ! Preparations for interpreting IC's

    ! RW dimensionality vars
    dimensionMask => this%TrackingOptions%dimensionMask
    nDim => this%TrackingOptions%nDim

    ! Process IC's
    read(icUnit, *) nInitialConditions
    write(outUnit,'(A,I5)') 'Given number of initial conditions = ', nInitialConditions
    nValidInitialConditions = 0
    particleCount = 0 

    if(nInitialConditions .le. 0) then
      ! No ic 
      write(outUnit,'(A)') 'Number of given initial conditions is .le. 0. Leaving the function.'
      return
    end if

    ! CellsPerLayer, required for u3d reader
    allocate(cellsPerLayer(grid%LayerCount))
    do n = 1, grid%LayerCount
      cellsPerLayer(n) = grid%GetLayerCellCount(n)
    end do

    ! Carrier for candidate particle groups 
    allocate(particleGroups(nInitialConditions))

    ! Loop over initial conditions
    do nic = 1, nInitialConditions
      
      ! Report which IC will be processed
      write(outUnit,'(A,I5)') 'Processing initial condition: ', nic

      ! Increase pgroup counter
      particleGroups(nic)%Group = this%ParticleGroupCount + nic

      ! Set release time for initial condition.
      ! It is an initial condition, then
      ! assumes release at referencetime
      initialReleaseTime = this%ReferenceTime
      call particleGroups(nic)%SetReleaseOption1(initialReleaseTime)

      ! Read id 
      read(icUnit, '(a)') particleGroups(nic)%Name

      ! Initial condition format
      ! 1: concentration
      read(icUnit, *) initialConditionFormat

      select case ( initialConditionFormat )
      ! Read initial condition as resident concentration (ML^-3)
      case (1) 
        ! Given a value for the mass of particles, 
        ! use flowModelData to compute cellvolume
        ! and a shape factor from which the number 
        ! of particles per cell is estimated

        if(allocated(densityDistribution)) deallocate(densityDistribution)
        allocate(densityDistribution(grid%CellCount))

        ! Read particles mass
        read(icUnit, *) particleMass

        if ( ( this%ParticlesMassOption .eq. 2 ) ) then 
          ! Read solute id
          ! Requires some validation/health check
          read(icUnit, *) soluteId
        end if

        ! Read concentration
        if((grid%GridType .eq. 1) .or. (grid%GridType .eq. 3)) then
          call u3ddblmp(icUnit, outUnit, grid%LayerCount, grid%RowCount,      &
            grid%ColumnCount, grid%CellCount, densityDistribution, aname(1))
        else if((grid%GridType .eq. 2) .or. (grid%GridType .eq. 4)) then
          call u3ddblmpusg(icUnit, outUnit, grid%CellCount, grid%LayerCount,  &
            densityDistribution, aname(1), cellsPerLayer)
        else
          write(outUnit,*) 'Invalid grid type specified when reading IC array ', & 
              particleGroups(nic)%Name, ' name. Stop.'
          call ustop('Invalid grid type specified when reading IC array') 
        end if

        ! Validity of initial condition
        ! Used to allocate subdivisions 
        validCellCounter = count( densityDistribution /= 0d0 )
        if( validCellCounter .eq.0 ) then
          write(outUnit,'(a,a,a)') 'Warning: initial condition ',&
                trim(particleGroups(nic)%Name),' has a distribution only with zeros'
          write(outUnit,'(a)') 'It will not create a particle group. Continue to the next.'
          ! Process the next one
          cycle
        end if 

        ! Allocate subdivisions
        if (allocated(subDivisions)) deallocate(subDivisions)
        allocate( subDivisions(validCellCounter,3) )
        subDivisions(:,:) = 0

        ! Loop over densityDistribution and compute:
        !  - totalDissolvedMass
        !  - totalAccumulatedMass: considers retardation factor
        !  - totalParticleCount
        totalDissolvedMass   = 0d0
        totalAccumulatedMass = 0d0
        totalParticleCount   = 0
        cellCounter          = 0
        do nc = 1, grid%CellCount
          ! If no concentration, next
          if ( densityDistribution(nc) .eq. 0d0 ) cycle

          ! Increase cellCounter
          cellCounter = cellCounter + 1

          ! Compute cell volume
          cellVolume = 1d0
          do nd=1,3
            if( dimensionMask(nd).eq.0 ) cycle
            select case(nd)
            case(1)
              cellVolume = cellVolume*grid%DelX(nc)
            case(2)
              cellVolume = cellVolume*grid%DelY(nc)
            case(3)
              ! simple dZ
              cellVolume = cellVolume*(grid%Top(nc)-grid%Bottom(nc))
            end select
          end do
          cellDissolvedMass = 0d0
          cellTotalMass = 0d0
          ! Absolute value is required for the weird case that 
          ! densityDistribution contains negative values
          cellDissolvedMass = abs(densityDistribution(nc))*porosity(nc)*cellVolume
          totalDissolvedMass = totalDissolvedMass + cellDissolvedMass 
          cellTotalMass = cellDissolvedMass*this%Retardation(nc)
          totalAccumulatedMass = totalAccumulatedMass + cellTotalMass
          
          ! nParticlesCell: estimate the number of particles 
          ! for the cell using the specified mass 
          nParticlesCell = cellTotalMass/particleMass

          ! If less than 0.5 particle, cycle to the next cell
          if ( nParticlesCell .lt. 0.5 ) cycle

          ! Compute shapeFactors only if dimension is active
          ! If not, will remain as zero
          sX = 0
          sY = 0
          sZ = 0
          do nd=1,3
            if( dimensionMask(nd).eq.0 ) cycle
            select case(nd)
            case(1)
              sX = grid%DelX(nc)/(cellVolume**(1d0/nDim))
            case(2)
              sY = grid%DelY(nc)/(cellVolume**(1d0/nDim))
            case(3)
              ! simple dZ
              sZ = (grid%Top(nc)-grid%Bottom(nc))/(cellVolume**(1d0/nDim))
            end select
          end do

          ! Estimate subdivisions
          nPX    = sX*( (nParticlesCell)**(1d0/nDim) ) 
          nPY    = sY*( (nParticlesCell)**(1d0/nDim) )
          nPZ    = sZ*( (nParticlesCell)**(1d0/nDim) )
          iNPX   = int( nPX ) + 1
          iNPY   = int( nPY ) + 1
          iNPZ   = int( nPZ ) + 1
          NPCELL = iNPX*iNPY*iNPZ
          totalParticleCount = totalParticleCount + NPCELL

          ! Save in subdivisions
          subDivisions(cellCounter,1) = iNPX
          subDivisions(cellCounter,2) = iNPY
          subDivisions(cellCounter,3) = iNPZ


        end do ! end loop over densityDistribution

        ! Assign totalParticleCount and continue to the next IC if no particles
        particleGroups(nic)%TotalParticleCount = totalParticleCount
        if ( totalParticleCount .eq. 0 ) then 
          write(outUnit,*) ' Warning: initial condition ',&
              particleGroups(nic)%Name,' has zero particles, it will skip this group.'
          ! Process the next one
          cycle
        end if 

        ! Allocate particles for this IC 
        if(allocated(particleGroups(nic)%Particles)) deallocate(particleGroups(nic)%Particles)
        allocate(particleGroups(nic)%Particles(totalParticleCount))

        ! effective particles mass
        effParticleMass = totalAccumulatedMass/totalParticleCount 
        write(outUnit,'(A,es18.9e3)') 'Original particle mass for initial condition = ', particleMass
        write(outUnit,'(A,es18.9e3)') 'Effective particle mass for initial condition = ', effParticleMass

        ! Yes ?
        ! Assign to the particle group 
        particleGroups(nic)%Mass = effParticleMass 

        ! Loop once again on densityDistribution to create particles
        m = 0
        cellCounter = 0
        do nc=1,grid%CellCount
          if ( densityDistribution(nc) .eq. 0d0 ) cycle

          cellCounter = cellCounter + 1

          ! Skip this cell if all subDivisions remained as zero
          if ( all( subDivisions( cellCounter, : ) .eq. 0 ) ) cycle

          ! For the weird requirement where density
          ! might be negative...
          if ( densityDistribution(nc) .gt. 0d0 ) then 
            particleMass = effParticleMass
          else ! If zero already cycled 
            particleMass = -1*effParticleMass
          end if

          ! 0: is for drape. TEMPORARY
          ! Drape = 0: particle placed in the cell. If dry, status to unreleased
          ! Drape = 1: particle placed in the uppermost active cell
          call CreateMassParticlesAsInternalArray(& 
            particleGroups(nic), nc, m, &
            subDivisions(cellCounter,1),&
            subDivisions(cellCounter,2),&
            subDivisions(cellCounter,3),& 
            0, particleMass, particleGroups(nic)%GetReleaseTime(1) )
        end do

        ! Assign layer value to each particle
        idmax = 0
        seqNumber = 0
        do m = 1, totalParticleCount
            seqNumber = seqNumber + 1
            if(particleGroups(nic)%Particles(m)%Id .gt. idmax) idmax = particleGroups(nic)%Particles(m)%Id
            particleGroups(nic)%Particles(m)%Group = particleGroups(nic)%Group
            particleGroups(nic)%Particles(m)%SequenceNumber = seqNumber
            particleGroups(nic)%Particles(m)%InitialLayer =                                   &
              grid%GetLayer(particleGroups(nic)%Particles(m)%InitialCellNumber)
            particleGroups(nic)%Particles(m)%Layer =                                          &
              grid%GetLayer(particleGroups(nic)%Particles(m)%CellNumber)
        end do

        ! Done with this IC kind

      case default
        write(outUnit,*) 'Invalid initial condition kind ', initialConditionFormat, '. Stop.' 
        call ustop('Invalid initial condition kind')
      end select

      ! Report about total mass and number of particles
      if(this%RetardationFactorOption .gt. 1) then
        write(outUnit,'(A)') 'Retardation factor is considered in total accumulated mass.'
        write(outUnit,'(A,es18.9e3)') 'Total disolved mass for initial condition = ', totalDissolvedMass
        write(outUnit,'(A,es18.9e3)') 'Total accumulated mass for initial condition = ', totalAccumulatedMass
      else 
        write(outUnit,'(A)') 'Retardation factor is unitary so total dissolved mass is the total mass.'
        write(outUnit,'(A,es18.9e3)') 'Total accumulated mass for initial condition = ', totalAccumulatedMass
      end if 
      write(outUnit,'(A,I10)') 'Total number of particles for this initial condition = ', totalParticleCount 

      ! Increment valid counter
      nValidInitialConditions = nValidInitialConditions + 1 

      ! Assign the solute id 
      if ( this%ParticlesMassOption .eq. 2 ) then 
        particleGroups(nic)%Solute = soluteId
      end if 

      ! Incremenent particleCount
      particleCount = particleCount + particleGroups(nic)%TotalParticleCount


    end do ! loop over initial conditions 
    write(outUnit, '(a,i10)') 'Total number of particles on initial conditions = ', particleCount
    write(outUnit, *)


    ! Extend simulationdata to include these particle groups
    if ( nValidInitialConditions .gt. 0 ) then 
      newParticleGroupCount = this%ParticleGroupCount + nValidInitialConditions
      allocate(newParticleGroups(newParticleGroupCount))
      ! If some particle groups existed previously
      if( this%ParticleGroupCount .gt. 0 ) then 
        do n = 1, this%ParticleGroupCount
          newParticleGroups(n) = this%ParticleGroups(n)
        end do
      end if 
      pgCount = 0
      do n = 1, nInitialConditions
        if ( particleGroups(n)%TotalParticleCount .eq. 0 ) cycle
        pgCount = pgCount + 1 
        newParticleGroups(pgCount+this%ParticleGroupCount) = particleGroups(n)
      end do 
      if( this%ParticleGroupCount .gt. 0 ) then 
        call move_alloc( newParticleGroups, this%ParticleGroups )
        this%ParticleGroupCount = newParticleGroupCount
        this%TotalParticleCount = this%TotalParticleCount + particleCount
      else
        this%ParticleGroupCount = newParticleGroupCount
        this%TotalParticleCount = particleCount
        allocate(this%ParticleGroups(this%ParticleGroupCount))
        call move_alloc( newParticleGroups, this%ParticleGroups )
      end if
    end if


    ! Close ic data file
    close( icUnit )


  end subroutine pr_ReadICData


  ! Read specific BC data
  subroutine pr_ReadBCData( this, bcFile, bcUnit, outUnit, grid )
    use UTL8MODULE,only : urword,ustop,u3dintmpusg, u3dintmp
    !--------------------------------------------------------------
    ! Specifications
    !--------------------------------------------------------------
    implicit none
    ! input 
    class(ModpathSimulationDataType), target     :: this
    character(len=200), intent(in)               :: bcFile
    integer, intent(in)                          :: bcUnit
    integer, intent(in)                          :: outUnit
    class(ModflowRectangularGridType),intent(in) :: grid
    ! local
    type(ParticleTrackingOptionsType), pointer :: trackingOptions
    integer :: isThisFileOpen = -1
    integer :: icol,istart,istop,n,nd,currentDim
    doubleprecision    :: r
    character(len=200) :: line
    integer, dimension(:), allocatable :: cellsPerLayer
    character(len=24),dimension(1) :: aname
    data aname(1) /'       ICBOUND'/
    integer :: nFluxConditions, nValidFluxConditions, particleCount
    integer :: nfc
    !--------------------------------------------------------------

    write(outUnit, *)
    write(outUnit, '(1x,a)') 'MODPATH-RW BC file data'
    write(outUnit, '(1x,a)') '-----------------------'

    ! CellsPerLayer, required for u3d reader
    allocate(cellsPerLayer(grid%LayerCount))
    do n = 1, grid%LayerCount
      cellsPerLayer(n) = grid%GetLayerCellCount(n)
    end do
    ! Allocate ICBound array, is needed downstream
    if(allocated(this%ICBound)) deallocate(this%ICBound)
    allocate(this%ICBound(grid%CellCount))

    ! Verify if unit is open 
    inquire( file=bcFile, number=isThisFileOpen )
    if ( isThisFileOpen .lt. 0 ) then 
      ! No bc file
      write(outUnit,'(A)') 'BC package was not specified in name file.'
      ! Initialize ICBound with only zeroes
      this%ICBound(:) = 0
      ! And leave
      return
    end if


    ! Read ICBOUND
    if((grid%GridType .eq. 1) .or. (grid%GridType .eq. 3)) then
      call u3dintmp(bcUnit, outUnit, grid%LayerCount, grid%RowCount,      &
        grid%ColumnCount, grid%CellCount, this%ICBound, aname(1))
    else if((grid%GridType .eq. 2) .or. (grid%GridType .eq. 4)) then
      call u3dintmpusg(bcUnit, outUnit, grid%CellCount, grid%LayerCount,  &
        this%ICBound, aname(1), cellsPerLayer)
    else
      write(outUnit,*) 'Invalid grid type specified when reading ICBOUND array data.'
      write(outUnit,*) 'Stopping.'
      call ustop(' ')          
    end if


    ! Preparations for interpreting additional BC's

    !! RW dimensionality vars
    !dimensionMask => this%TrackingOptions%dimensionMask
    !nDim => this%TrackingOptions%nDim
    
    !! Read FLUX BC's
    !read(bcUnit, *) nFluxConditions
    !write(outUnit,'(A,I5)') 'Given number of flux boundary conditions = ', nFluxConditions
    !nValidFluxConditions = 0 ! Monitors whether the boundary has any particle
    !particleCount = 0

    !if(nFluxConditions .le. 0) then
    !  ! No flux  
    !  ! It shall continue to the next BC kind
    !  write(outUnit,'(A)') 'Number of given flux conditions is .le. 0. Leaving the function.'
    !  return
    !end if

    !! Carrier for candidate particle groups 
    !allocate(particleGroups(nFluxConditions))
 
    !! Loop over flux conditions
    !do nfc = 1, nFluxConditions
    !  
    !  ! Report which FLUX BC will be processed
    !  write(outUnit,'(A,I5)') 'Processing flux boundary condition: ', nfc

    !  ! Increase pgroup counter
    !  particleGroups(nfc)%Group = this%ParticleGroupCount + nfc

    !end do


    ! Close bc data file
    close( bcUnit )


  end subroutine pr_ReadBCData


end module ModpathSimulationDataModule
