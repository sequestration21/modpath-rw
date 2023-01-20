module GlobalDataModule
    implicit none
    integer, save :: narealsp, issflg, nper
    integer, save :: mpbasUnit, disUnit, tdisUnit, gridMetaUnit, headUnit,       &
      headuUnit, budgetUnit, traceModeUnit, binPathlineUnit
    integer, save :: inUnit, pathlineUnit, endpointUnit, timeseriesUnit,        &
      mplistUnit, mpsimUnit, traceUnit, budchkUnit, aobsUnit, logUnit
    integer, save :: dispersionUnit, gpkdeUnit, obsUnit, dspUnit, rwoptsUnit ! RWPT 
    integer, save :: particleGroupCount
    integer, save :: gridFileType
    integer, save :: logType
    integer, parameter :: niunit = 100
    character*200 :: mpnamFile, mpsimFile, mplistFile, mpbasFile, disFile,      &
      tdisFile, gridFile, headFile, budgetFile, traceFile, gridMetaFile,        &
      mplogFile, gpkdeFile, obsFile, dspFile, rwoptsFile ! RWPT
end module
