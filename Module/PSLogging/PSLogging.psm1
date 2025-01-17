﻿###
# Modifyed by CyberblueX
# Setting default parameter for Logfile Name to System UUID
# Added Time measure functions
# Changed all functions to use LogPath & Logname Parameter
# Added System Information Block
# Added FileLock Test
# Changed To UTC TimeStamp and moved to beginning of lines
# Changed Output format with PadRight
# Added Support for running under WindowPE v5 & v10
# Added Support for WinEvent Logging
###

### 
# Orginal from
# Author: Luca Sturlese
# URL: http://9to5IT.com
# Module PSLogging in Version 2.5.2
###

Set-StrictMode -Version Latest


Function Start-Log {
  <#
  .SYNOPSIS
    Creates a new log file

  .DESCRIPTION
    Creates a log file with the path and name specified in the parameters. Checks if log file exists, and if it does deletes it and creates a new one.
    Once created, writes initial logging data

  .PARAMETER LogPath
    Mandatory. Path of where log is to be created. Example: C:\Windows\Temp

  .PARAMETER LogName
    Mandatory. Name of log file to be created. Example: Test_Script.log

  .PARAMETER ScriptVersion
    Mandatory. Version of the running script which will be written in the log. Example: 1.5

  .PARAMETER ToScreen
    Optional. When parameter specified will display the content to screen as well as write to log file. This provides an additional
    another option to write content to screen as opposed to using debug mode.

  .INPUTS
    Parameters above

  .OUTPUTS
    Log file created

  .NOTES
    Version:        1.0
    Author:         Luca Sturlese
    Creation Date:  10/05/12
    Purpose/Change: Initial function development.

    Version:        1.1
    Author:         Luca Sturlese
    Creation Date:  19/05/12
    Purpose/Change: Added debug mode support.

    Version:        1.2
    Author:         Luca Sturlese
    Creation Date:  02/09/15
    Purpose/Change: Changed function name to use approved PowerShell Verbs. Improved help documentation.

    Version:        1.3
    Author:         Luca Sturlese
    Creation Date:  07/09/15
    Purpose/Change: Resolved issue with New-Item cmdlet. No longer creates error. Tested - all ok.

    Version:        1.4
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Added -ToScreen parameter which will display content to screen as well as write to the log file.

  .LINK
    http://9to5IT.com/powershell-logging-v2-easily-create-log-files

  .EXAMPLE
    Start-Log -LogPath "C:\Windows\Temp" -LogName "Test_Script.log" -ScriptVersion "1.5"

    Creates a new log file with the file path of C:\Windows\Temp\Test_Script.log. Initialises the log file with
    the date and time the log was created (or the calling script started executing) and the calling script's version.
  #>

  [CmdletBinding()]

  Param (
    [Parameter(Mandatory=$false,Position=0)][string]$LogPath = ($env:TEMP),
    [Parameter(Mandatory=$false,Position=1)][string]$LogName = ((Get-WmiObject Win32_computerSystemproduct -Property UUID).UUID + ".log"),
    [Parameter(Mandatory=$false,Position=2)][version]$ScriptVersion = "1.0.0.0",
    [Parameter(Mandatory=$false,Position=3)][switch]$ToScreen,
    [Parameter(Mandatory=$false,Position=4)][switch]$noLogSystemInfo,
    [Parameter(Mandatory=$false,Position=5)][switch]$DeleteOld,
    [Parameter(Mandatory=$false,Position=6)][switch]$EnableWinEventlog,
    [Parameter(Mandatory=$false,Position=7)][string]$WinEventlog_Name="Application",
    [Parameter(Mandatory=$false,Position=8)][string]$WinEventlog_Source="PSLogging"
  )

  Process {
    
    IF( ($LogName.Split(".")[$LogName.Split(".").Count-1]) -ne "log") { $LogName = $LogName + ".log" }
    $sFullPath = Join-Path -Path $LogPath -ChildPath $LogName
    $script:sLogPathShared = $LogPath
    $sScriptFullPath =  $($MyInvocation.ScriptName)
    $script:sStartTime = (Get-Date).ToUniversalTime()
    $sSIBstart_str = "System Information Block"
    $sSIBend_str = "END: System Information Block"
    $script:sEnableWinEventlog = $EnableWinEventlog
    $script:sWinEventlog_Name = $WinEventlog_Name
    $script:sWinEventlog_Source = $WinEventlog_Source

    #region WinEvent Logging
    IF ($EnableWinEventlog) {
        IF (!([system.diagnostics.eventlog]::SourceExists("$sWinEventlog_Source"))) {
            IF (!([system.diagnostics.eventlog]::Exists($sWinEventlog_Name))) {
                New-EventLog –LogName $sWinEventlog_Name –Source $sWinEventlog_Source
                Limit-EventLog -LogName $sWinEventlog_Name -MaximumSize 524288 -OverFlowAction OverwriteOlder -RetentionDays 360 -ErrorAction SilentlyContinue
            } ELSE {
                New-EventLog –LogName $sWinEventlog_Name –Source $sWinEventlog_Source
            }
        } ELSE {
            $sSourceLog = [system.diagnostics.eventlog]::LogNameFromSourceName($sWinEventlog_Source,".")
            IF ( $sSourceLog -ne $sWinEventlog_Name -and $sSourceLog -ne "") {
                $script:sWinEventlog_Name = [system.diagnostics.eventlog]::LogNameFromSourceName($sWinEventlog_Source,".")
            }
            Write-Debug "Using existing Eventlog $sWinEventlog_Name with Source $sWinEventlog_Source"
        }         
    } #endregion

    #region Check if file exists or create new
    If ( (Test-Path -Path $sFullPath) -and ( $DeleteOld -eq $True ) ) {
        #delete if it does and Switch is on
        $sCreateNew = $true
        
        Edit-FileWait -Path $sFullPath -Scriptblock {
          $null = Remove-Item -Path $sFullPath -Force
          $null = New-Item -Path $sFullPath –ItemType File
        }

    } ELSEIF (Test-Path -Path $sFullPath) {
        #if exist and switch is off
        $sCreateNew = $false
        #Do Nothing
    } ELSE {
        #Create file and start logging
        $sCreateNew = $true
        $null = New-Item -Path $sFullPath –ItemType File
    } 
    #endregion

    # If switch isn't Set Log System Information
    IF ($noLogSystemInfo -eq $False) {

        #region Detect running in Windows PE and do other tasks
        IF (($env:SystemDrive -like "X:") -or (((Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID) -like "WindowsPE")) {
            $sStatus_runningpe = $true
            $sPE_reg_info = Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinPE"
            $sPE_version =  $sPE_reg_info.Version
            $sPE_version2 = $sPE_reg_info.Version.Split(".")[0]
        }
        ELSE {
            $sStatus_runningpe = $false
        }
        #endregion
        
        # Get System Informations
        $sComputerSystemproduct = Get-WmiObject Win32_computerSystemproduct -Property UUID, vendor, name
        $sComputerSystem = Get-WmiObject Win32_computerSystem -Property TotalPhysicalMemory
        $sBios = Get-WmiObject win32_bios -Property manufacturer, serialnumber, biosversion
        $sProcessor = Get-WmiObject Win32_processor -Property Name, NumberOfCores, NumberOfLogicalProcessors, VirtualizationFirmwareEnabled
        $sDiskDrive = Get-WmiObject Win32_DiskDrive -Property Index, Model, Size

        # Vars
        $sSIB_exist = $false

        $sSysInfo_System_UUID               = $sComputerSystemproduct.UUID
        $sSysInfo_Computername              = $env:COMPUTERNAME
        $sSysInfo_PC_Manufacturer           = $sComputerSystemproduct.vendor
        $sSysInfo_PC_Product_Name           = $sComputerSystemproduct.name
        $sSysInfo_PC_PhysMemoryMB           = [math]::Round($sComputerSystem.TotalPhysicalMemory/1mb)
        $sSysInfo_BIOS_Manufacturer         = $sBios.manufacturer
        $sSysInfo_BIOS_Serial               = $sBios.serialnumber
        $sSysInfo_BIOS_Version              = $sBios.biosversion
        $sSysInfo_CPU_Name                  = $sProcessor.Name
        $sSysInfo_CPU_Cores                 = $sProcessor.NumberOfCores
        $sSysInfo_CPU_LogicalProcessors     = $sProcessor.NumberOfLogicalProcessors
        $sSysInfo_CPU_VMEnabled             = $sProcessor.VirtualizationFirmwareEnabled
        if ($sStatus_runningpe) {
            $snetwork_phys_adapter1 = Get-WmiObject win32_networkadapter -Filter "PhysicalAdapter=true"
            $snetwork_info1 = %{$snetwork_phys_adapter1.GetRelated('win32_networkadapterconfiguration')}
            $OFS = " ; "
            $sSysInfo_Net_Interfaces            = @( ($snetwork_phys_adapter1).Description )
            $sSysInfo_Net_MACs                  = @( ($snetwork_phys_adapter1).MacAddress )
            $sSysInfo_Net_IPv4s                 = @(($snetwork_info1).IPAddress.Where({$_ -match "\b(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}\b"}))
            $sSysInfo_Net_IPv6s                 = @()
        } ELSE {
            $OFS = " ; "
            $sSysInfo_Net_Interfaces            = @((Get-NetAdapter -Physical).InterfaceDescription)
            $sSysInfo_Net_MACs                  = @((Get-NetAdapter -Physical).MacAddress)
            $sSysInfo_Net_IPv4s                 = @((Get-NetAdapter -Physical | Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress)
            $sSysInfo_Net_IPv6s                 = @((Get-NetAdapter -Physical | Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue).IPAddress)
        }
        
        If (!$sCreateNew) {

            $sFileHead = Get-Content -Path $sFullPath -TotalCount 50

            IF (!$sFileHead.Where{$_ -eq $sSIBstart_str} -or !$sFileHead.Where{$_ -eq $sSIBend_str}) {
            
                Write-Debug "No Informationblock found. Adding new..."

                $sSysInfo_Computername_Set = $sSysInfo_Computername
                $sSysinfo_Logcreated_Set = ((Get-Date).ToUniversalTime().ToString() + " UTC")
                
                $sLogfile_Content_old = Get-Content -Path $sFullPath
               
            } ELSE {
            
                $sSIB_exist = $true

                $sSysInfo_firstline = $sFileHead.Where{$_ -eq $sSIBstart_str}.ReadCount[0] + 1
                $sSysInfo_lastline = $sFileHead.Where{$_ -eq $sSIBend_str}.ReadCount[0] - 1

                #Write-Debug "sSysInfo_firstline= $sSysInfo_firstline"
                #Write-Debug "sSysInfo_lastline= $sSysInfo_lastline"

                $sSysInfo_Output = Get-Content -Path $sFullPath | Where-Object {$_.readcount -in $sSysInfo_firstline..$sSysInfo_lastline}

                $sSysInfo_Values = @()
                $sSysInfo_Values2 = New-Object System.Object
           
                ForEach ($line in $sSysInfo_Output) {
            
                    $line_filter = $line.Split("=").Replace('"',"").Trim()

                    #Variant 1
                    $sSysInfo_Value = New-Object System.Object
                    $sSysInfo_Value | Add-Member -type NoteProperty -name Name -value $line_filter[0]
                    $sSysInfo_Value | Add-Member -type NoteProperty -name Info -value $line_filter[1]
                    $sSysInfo_Values += $sSysInfo_Value

                    #Variant 2
                    Add-Member -InputObject $sSysInfo_Values2 -NotePropertyName $line_filter[0].Replace(' ',"_") -NotePropertyValue $line_filter[1] -Force
                } 

         #       ForEach ($line in $sSysInfo_Values) {
         #
         #           Write-Debug ($line.Name + "`t=`t" + $line.Info)
         #
         #       }

         #       Example to Grab Info
         #       $example = ($sSysInfo_Values.Where{$_.Name -eq "Disk0"}).Info
         #       $example = $sSysInfo_Values | Where-Object {$_.Name -eq "Disk0"} | select Info
         #       Write-Host $example

                IF ($sSysInfo_Values2.Known_Computernames -notlike "*$sSysInfo_Computername*") {
                    $sSysInfo_Computername_Set = ($sSysInfo_Values2.Known_Computernames + " ; " + $sSysInfo_Computername)
                } ELSE {
                    $sSysInfo_Computername_Set = $sSysInfo_Computername                
                }

                $sSysinfo_Logcreated_Set = $sSysInfo_Values2.Log_created

                $sLogfile_Content_old = Get-Content -Path $sFullPath | Where-Object {$_.readcount -ge ($sSysInfo_lastline + 3)}
          }

                
                
                $sLogfile_Content_add  = @()
                $sLogfile_Content_add += "***************************************************************************************************"
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += $sSIBstart_str
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"Log created"             = "' + $sSysinfo_Logcreated_Set + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"Last Script run"         = "' + ((Get-Date).ToUniversalTime().ToString()) + " UTC" + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"System UUID"             = "' + $sSysInfo_System_UUID + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"Known Computernames"     = "' + $sSysInfo_Computername_Set + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"PC Manufacturer"         = "' + $sSysInfo_PC_Manufacturer + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"PC Product Name"         = "' + $sSysInfo_PC_Product_Name + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"PC PhyisMemory"          = "' + $sSysInfo_PC_PhysMemoryMB + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"BIOS Manufacturer"       = "' + $sSysInfo_BIOS_Manufacturer + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"BIOS Serial"             = "' + $sSysInfo_BIOS_Serial + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"BIOS Version"            = "' + $sSysInfo_BIOS_Version + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"CPU Name"                = "' + $sSysInfo_CPU_Name + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"CPU Cores"               = "' + $sSysInfo_CPU_Cores + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"CPU LogicalProcessors"   = "' + $sSysInfo_CPU_LogicalProcessors + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"CPU VM Enabled"          = "' + $sSysInfo_CPU_VMEnabled + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"Network Interfaces"      = "' + $sSysInfo_Net_Interfaces + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"Network MACs"            = "' + $sSysInfo_Net_MACs + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"Network IPv4s"           = "' + $sSysInfo_Net_IPv4s + '"')
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += ('"Network IPv6s"           = "' + $sSysInfo_Net_IPv6s + '"')
            #    $sLogfile_Content_add += "`r`n"
                foreach ($disk in $sDiskDrive) { 
                $sLogfile_Content_add += '"Disk' + $disk.Index + '"                   = "' + $disk.Model + " ; " + ([math]::Round($disk.Size/1gb))+ "GB" + " ; " + ([math]::Round($disk.Size/1gb))+ "GB" + '"'
            #    $sLogfile_Content_add += "`r`n"
                }
                $sLogfile_Content_add += $sSIBend_str
            #    $sLogfile_Content_add += "`r`n"
                $sLogfile_Content_add += "***************************************************************************************************"  
            #    $sLogfile_Content_add += "`r`n"
                
                #$OFS = "`r`n"
                $sLogfile_Content_new = $sLogfile_Content_add + $sLogfile_Content_old

                Edit-FileWait -Path $sFullPath -Scriptblock {
                  Set-Content -Path $sFullPath -Value  $sLogfile_Content_new
                }
            

        } ELSE {
          $sLogfile_Content_new  = @()
          $sLogfile_Content_new += "***************************************************************************************************"
          $sLogfile_Content_new += $sSIBstart_str
          $sLogfile_Content_new += ('"Log created"             = "' + ((Get-Date).ToUniversalTime().ToString()) + " UTC" + '"')
          $sLogfile_Content_new += ('"Last Script run"         = "' + ((Get-Date).ToUniversalTime().ToString()) + " UTC" + '"')
          $sLogfile_Content_new += ('"System UUID"             = "' + $sSysInfo_System_UUID + '"')
          $sLogfile_Content_new += ('"Known Computernames"     = "' + $sSysInfo_Computername + '"')
          $sLogfile_Content_new += ('"PC Manufacturer"         = "' + $sSysInfo_PC_Manufacturer + '"')
          $sLogfile_Content_new += ('"PC Product Name"         = "' + $sSysInfo_PC_Product_Name + '"')
          $sLogfile_Content_new += ('"PC PhyisMemory"          = "' + $sSysInfo_PC_PhysMemoryMB + '"')
          $sLogfile_Content_new += ('"BIOS Manufacturer"       = "' + $sSysInfo_BIOS_Manufacturer + '"')
          $sLogfile_Content_new += ('"BIOS Serial"             = "' + $sSysInfo_BIOS_Serial + '"')
          $sLogfile_Content_new += ('"BIOS Version"            = "' + $sSysInfo_BIOS_Version + '"')
          $sLogfile_Content_new += ('"CPU Name"                = "' + $sSysInfo_CPU_Name + '"')
          $sLogfile_Content_new += ('"CPU Cores"               = "' + $sSysInfo_CPU_Cores + '"')
          $sLogfile_Content_new += ('"CPU LogicalProcessors"   = "' + $sSysInfo_CPU_LogicalProcessors + '"')
          $sLogfile_Content_new += ('"CPU VM Enabled"          = "' + $sSysInfo_CPU_VMEnabled + '"')
          $sLogfile_Content_new += ('"Network Interfaces"      = "' + $sSysInfo_Net_Interfaces + '"')
          $sLogfile_Content_new += ('"Network MACs"            = "' + $sSysInfo_Net_MACs + '"')
          $sLogfile_Content_new += ('"Network IPv4s"           = "' + $sSysInfo_Net_IPv4s + '"')
          $sLogfile_Content_new += ('"Network IPv6s"           = "' + $sSysInfo_Net_IPv6s + '"')
          foreach ($disk in $sDiskDrive) { 
          $sLogfile_Content_new += '"Disk' + $disk.Index + '"                   = "' + $disk.Model + " ; " + ([math]::Round($disk.Size/1gb))+ "GB" + '"'
          }
          $sLogfile_Content_new += $sSIBend_str
          $sLogfile_Content_new += "***************************************************************************************************"  
                
          Edit-FileWait -Path $sFullPath -Scriptblock {
              #Create new File Header
              Add-Content -Path $sFullPath -Value $sLogfile_Content_new
             # Add-Content -Path $sFullPath -Value "***************************************************************************************************"
             # Add-Content -Path $sFullPath -Value $sSIBstart_str
             # Add-Content -Path $sFullPath -Value ('"Log created"             = "' + ((Get-Date).ToUniversalTime().ToString()) + " UTC" + '"')
             # Add-Content -Path $sFullPath -Value ('"System UUID"             = "' + $sSysInfo_System_UUID + '"')
             # Add-Content -Path $sFullPath -Value ('"Known Computernames"     = "' + $sSysInfo_Computername + '"')
             # Add-Content -Path $sFullPath -Value ('"PC Manufacturer"         = "' + $sSysInfo_PC_Manufacturer + '"')
             # Add-Content -Path $sFullPath -Value ('"PC Product Name"         = "' + $sSysInfo_PC_Product_Name + '"')
             # Add-Content -Path $sFullPath -Value ('"PC PhyisMemory"          = "' + $sSysInfo_PC_PhysMemoryMB + '"')
             # Add-Content -Path $sFullPath -Value ('"BIOS Manufacturer"       = "' + $sSysInfo_BIOS_Manufacturer + '"')
             # Add-Content -Path $sFullPath -Value ('"BIOS Serial"             = "' + $sSysInfo_BIOS_Serial + '"')
             # Add-Content -Path $sFullPath -Value ('"BIOS Version"            = "' + $sSysInfo_BIOS_Version + '"')
             # Add-Content -Path $sFullPath -Value ('"CPU Name"                = "' + $sSysInfo_CPU_Name + '"')
             # Add-Content -Path $sFullPath -Value ('"CPU Cores"               = "' + $sSysInfo_CPU_Cores + '"')
             # Add-Content -Path $sFullPath -Value ('"CPU LogicalProcessors"   = "' + $sSysInfo_CPU_LogicalProcessors + '"')
             # Add-Content -Path $sFullPath -Value ('"CPU VM Enabled"          = "' + $sSysInfo_CPU_VMEnabled + '"')
             # Add-Content -Path $sFullPath -Value ('"Network Interfaces"      = "' + $sSysInfo_Net_Interfaces + '"')
             # Add-Content -Path $sFullPath -Value ('"Network MACs"            = "' + $sSysInfo_Net_MACs + '"')
             # Add-Content -Path $sFullPath -Value ('"Network IPv4s"           = "' + $sSysInfo_Net_IPv4s + '"')
             # foreach ($disk in $sDiskDrive) { 
             # $tmp_line = '"Disk' + $disk.Index + '"                   = "' + $disk.Model + " ; " + ([math]::Round($disk.Size/1gb))+ "GB" + " ; " + ([math]::Round($disk.Size/1gb))+ "GB" + '"'
             # Add-Content -Path $sFullPath -Value $tmp_line
             # }
             # Add-Content -Path $sFullPath -Value $sSIBend_str
             # Add-Content -Path $sFullPath -Value "***************************************************************************************************"
              
        }
      }
                        
    } ELSE {
        Edit-FileWait -Path $sFullPath -Scriptblock {
          Add-Content -Path $sFullPath -Value "***************************************************************************************************"
        }
    }

$str = @"
Started processing at [$((Get-Date).ToUniversalTime().ToString()) UTC].
***************************************************************************************************

Running Script $sScriptFullPath
Version [$ScriptVersion]

***************************************************************************************************
"@

    #Write to WinEventlog
    IF ($sEnableWinEventlog){
      Write-EventLog –LogName $sWinEventlog_Name –Source $sWinEventlog_Source –EntryType Information –EventID 1 –Message $str
    }

    #Write to Logfile
    Edit-FileWait -Path $sFullPath -Scriptblock {
      Add-Content -Path $sFullPath -Value $str
    }

    #Write to screen for debug mode
    Write-Debug "***************************************************************************************************"
    Write-Debug "Started processing at [$((Get-Date).ToUniversalTime().ToString()) UTC]."
    Write-Debug "***************************************************************************************************"
    Write-Debug ""
    Write-Debug "Running Script $sScriptFullPath"
    Write-Debug "Running script version [$ScriptVersion]."
    Write-Debug ""
    Write-Debug "***************************************************************************************************"
    Write-Debug ""

    #Write to scren for ToScreen mode
    If ( $ToScreen -eq $True ) {
      Write-Output "***************************************************************************************************"
      Write-Output "Started processing at [$((Get-Date).ToUniversalTime().ToString()) UTC]."
      Write-Output "***************************************************************************************************"
      Write-Output ""
      Write-Output "Running Script $sScriptFullPath"
      Write-Output "Running script version [$ScriptVersion]."
      Write-Output ""
      Write-Output "***************************************************************************************************"
      Write-Output ""
    }
  }
}

Function Write-LogInfo {
  <#
  .SYNOPSIS
    Writes informational message to specified log file

  .DESCRIPTION
    Appends a new informational message to the specified log file

  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to write to. Example: C:\Windows\Temp\Test_Script.log

  .PARAMETER Message
    Mandatory. The string that you want to write to the log

  .PARAMETER TimeStamp
    Optional. When parameter specified will append the current date and time to the end of the line. Useful for knowing
    when a task started and stopped.

  .PARAMETER ToScreen
    Optional. When parameter specified will display the content to screen as well as write to log file. This provides an additional
    another option to write content to screen as opposed to using debug mode.

  .INPUTS
    Parameters above

  .OUTPUTS
    None

  .NOTES
    Version:        1.0
    Author:         Luca Sturlese
    Creation Date:  10/05/12
    Purpose/Change: Initial function development.

    Version:        1.1
    Author:         Luca Sturlese
    Creation Date:  19/05/12
    Purpose/Change: Added debug mode support.

    Version:        1.2
    Author:         Luca Sturlese
    Creation Date:  02/09/15
    Purpose/Change: Changed function name to use approved PowerShell Verbs. Improved help documentation.

    Version:        1.3
    Author:         Luca Sturlese
    Creation Date:  02/09/15
    Purpose/Change: Changed parameter name from LineValue to Message to improve consistency across functions.

    Version:        1.4
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Added -TimeStamp parameter which append a timestamp to the end of the line. Useful for knowing when a task started and stopped.

    Version:        1.5
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Added -ToScreen parameter which will display content to screen as well as write to the log file.

  .LINK
    http://9to5IT.com/powershell-logging-v2-easily-create-log-files

  .EXAMPLE
    Write-LogInfo -LogPath "C:\Windows\Temp\Test_Script.log" -Message "This is a new line which I am appending to the end of the log file."

    Writes a new informational log message to a new line in the specified log file.
  #>

  [CmdletBinding()]

  Param (
    [Parameter(Mandatory=$false,Position=0)][string]$LogPath=$sLogPathShared,
    [Parameter(Mandatory=$false,Position=1)][string]$LogName=((Get-WmiObject Win32_computerSystemproduct -Property UUID).UUID + ".log"),
    [Parameter(Mandatory=$true,Position=2,ValueFromPipeline=$true)][string]$Message,
    [Parameter(Mandatory=$false,Position=3)][switch]$noTimeStamp,
    [Parameter(Mandatory=$false,Position=4)][switch]$ToScreen,
    [Parameter(Mandatory=$false,Position=5)][string]$ForegroundColor,
    [Parameter(Mandatory=$false)][switch]$noEventlog
  )

  Process {
    
    $sFullPath = Join-Path -Path $LogPath -ChildPath $LogName
    
    #Add TimeStamp to message if specified
    If ( $noTimeStamp -eq $False ) {
      $Prefix  = ("[$((Get-Date).ToUniversalTime().ToString()) UTC]").PadRight(38)  
      $Message = $Prefix + $Message
    } ELSE {
      $Message = ((" ").PadRight(12) + $Message)
    }
    
    #Write to WinEventlog
    IF ($sEnableWinEventlog -and !$noEventlog) {
      Write-EventLog –LogName $sWinEventlog_Name –Source $sWinEventlog_Source –EntryType Information –EventID 1 –Message $Message
    }

    #Write Content to Log
    Edit-FileWait -Path $sFullPath -Scriptblock {
      Add-Content -Path $sFullPath -Value $Message
    }

    #Write to screen for debug mode
    Write-Debug $Message

    #Write to scren for ToScreen mode
    If ( $ToScreen -eq $True ) {
      IF ($ForegroundColor) {
        Write-Host -ForegroundColor $ForegroundColor $Message
      } ELSE {
        Write-Output $Message
      }
    }
  }
}

Function Write-LogWarning {
  <#
  .SYNOPSIS
    Writes warning message to specified log file

  .DESCRIPTION
    Appends a new warning message to the specified log file. Automatically prefixes line with WARNING:

  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to write to. Example: C:\Windows\Temp\Test_Script.log

  .PARAMETER Message
    Mandatory. The string that you want to write to the log

  .PARAMETER TimeStamp
    Optional. When parameter specified will append the current date and time to the end of the line. Useful for knowing
    when a task started and stopped.

  .PARAMETER ToScreen
    Optional. When parameter specified will display the content to screen as well as write to log file. This provides an additional
    another option to write content to screen as opposed to using debug mode.

  .INPUTS
    Parameters above

  .OUTPUTS
    None

  .NOTES
    Version:        1.0
    Author:         Luca Sturlese
    Creation Date:  02/09/15
    Purpose/Change: Initial function development.

    Version:        1.1
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Added -TimeStamp parameter which append a timestamp to the end of the line. Useful for knowing when a task started and stopped.

    Version:        1.2
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Added -ToScreen parameter which will display content to screen as well as write to the log file.

  .LINK
    http://9to5IT.com/powershell-logging-v2-easily-create-log-files

  .EXAMPLE
    Write-LogWarning -LogPath "C:\Windows\Temp\Test_Script.log" -Message "This is a warning message."

    Writes a new warning log message to a new line in the specified log file.
  #>

  [CmdletBinding()]

  Param (
    [Parameter(Mandatory=$false,Position=0)][string]$LogPath=$sLogPathShared,
    [Parameter(Mandatory=$false,Position=1)][string]$LogName=((Get-WmiObject Win32_computerSystemproduct -Property UUID).UUID + ".log"),
    [Parameter(Mandatory=$true,Position=2,ValueFromPipeline=$true)][string]$Message,
    [Parameter(Mandatory=$false,Position=3)][switch]$noTimeStamp,
    [Parameter(Mandatory=$false,Position=4)][switch]$ToScreen,
    [Parameter(Mandatory=$false)][switch]$noEventlog
  )

  Process {
    
    $sFullPath = Join-Path -Path $LogPath -ChildPath $LogName
    
    #Add TimeStamp to message if specified
    If ( $noTimeStamp -eq $False ) {
      $Prefix  = ("[$((Get-Date).ToUniversalTime().ToString()) UTC] WARNING:").PadRight(38)  
      $Message = $Prefix + $Message
    } ELSE {
      $Message = (("WARNING:").PadRight(12) + $Message)
    }
 
    #Write to WinEventlog
    IF ($sEnableWinEventlog -and !$noEventlog) {
      Write-EventLog –LogName $sWinEventlog_Name –Source $sWinEventlog_Source –EntryType Warning –EventID 3 –Message $Message
    }

    #Write Content to Log
    Edit-FileWait -Path $sFullPath -Scriptblock {
      Add-Content -Path $sFullPath -Value $Message
    }

    #Write to screen for debug mode
    Write-Debug $Message

    #Write to scren for ToScreen mode
    If ( $ToScreen -eq $True ) {
      Write-Host -ForegroundColor Yellow $Message
    }
  }
}

Function Write-LogError {
  <#
  .SYNOPSIS
    Writes error message to specified log file

  .DESCRIPTION
    Appends a new error message to the specified log file. Automatically prefixes line with ERROR:

  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to write to. Example: C:\Windows\Temp\Test_Script.log

  .PARAMETER Message
    Mandatory. The description of the error you want to pass (pass your own or use $_.Exception)

  .PARAMETER TimeStamp
    Optional. When parameter specified will append the current date and time to the end of the line. Useful for knowing
    when a task started and stopped.

  .PARAMETER ExitGracefully
    Optional. If parameter specified, then runs Stop-Log and then exits script

  .PARAMETER ToScreen
    Optional. When parameter specified will display the content to screen as well as write to log file. This provides an additional
    another option to write content to screen as opposed to using debug mode.

  .INPUTS
    Parameters above

  .OUTPUTS
    None

  .NOTES
    Version:        1.0
    Author:         Luca Sturlese
    Creation Date:  10/05/12
    Purpose/Change: Initial function development.

    Version:        1.1
    Author:         Luca Sturlese
    Creation Date:  19/05/12
    Purpose/Change: Added debug mode support. Added -ExitGracefully parameter functionality.

    Version:        1.2
    Author:         Luca Sturlese
    Creation Date:  02/09/15
    Purpose/Change: Changed function name to use approved PowerShell Verbs. Improved help documentation.

    Version:        1.3
    Author:         Luca Sturlese
    Creation Date:  02/09/15
    Purpose/Change: Changed parameter name from ErrorDesc to Message to improve consistency across functions.

    Version:        1.4
    Author:         Luca Sturlese
    Creation Date:  03/09/15
    Purpose/Change: Improved readability and cleaniness of error writing.

    Version:        1.5
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Changed -ExitGracefully parameter to switch type so no longer need to specify $True or $False (see example for info).

    Version:        1.6
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Added -TimeStamp parameter which append a timestamp to the end of the line. Useful for knowing when a task started and stopped.

    Version:        1.7
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Added -ToScreen parameter which will display content to screen as well as write to the log file.

  .LINK
    http://9to5IT.com/powershell-logging-v2-easily-create-log-files

  .EXAMPLE
    Write-LogError -LogPath "C:\Windows\Temp\Test_Script.log" -Message $_.Exception -ExitGracefully

    Writes a new error log message to a new line in the specified log file. Once the error has been written,
    the Stop-Log function is excuted and the calling script is exited.

  .EXAMPLE
    Write-LogError -LogPath "C:\Windows\Temp\Test_Script.log" -Message $_.Exception

    Writes a new error log message to a new line in the specified log file, but does not execute the Stop-Log
    function, nor does it exit the calling script. In other words, the only thing that occurs is an error message
    is written to the log file and that is it.

    Note: If you don't specify the -ExitGracefully parameter, then the script will not exit on error.
  #>

  [CmdletBinding()]

  Param (
    [Parameter(Mandatory=$false,Position=0)][string]$LogPath=$sLogPathShared,
    [Parameter(Mandatory=$false,Position=1)][string]$LogName=((Get-WmiObject Win32_computerSystemproduct -Property UUID).UUID + ".log"),
    [Parameter(Mandatory=$true,Position=2,ValueFromPipeline=$true)][string]$Message,
    [Parameter(Mandatory=$false,Position=3)][switch]$noTimeStamp,
    [Parameter(Mandatory=$false,Position=4)][switch]$ExitGracefully,
    [Parameter(Mandatory=$false,Position=5)][switch]$ToScreen,
    [Parameter(Mandatory=$false)][switch]$noEventlog
  )

  Process {
    
    $sFullPath = Join-Path -Path $LogPath -ChildPath $LogName
    
    #Add TimeStamp to message if specified
    If ( $noTimeStamp -eq $false ) {
      $Prefix  = ("[$((Get-Date).ToUniversalTime().ToString()) UTC] ERROR:").PadRight(38) 
      $Message = $Prefix + $Message
    } ELSE {
      $Message = (("ERROR:").PadRight(12) + $Message)
    }

    #Write Content to Log
    Edit-FileWait -Path $sFullPath -Scriptblock {
      Add-Content -Path $sFullPath -Value $Message
    }

    #Write to WinEventlog
    IF ($sEnableWinEventlog -and !$noEventlog) {
      Write-EventLog –LogName $sWinEventlog_Name –Source $sWinEventlog_Source –EntryType Error –EventID 4 –Message $Message
    }

    #Write to screen for debug mode
    Write-Debug $Message

    #Write to scren for ToScreen mode
    If ( $ToScreen -eq $True ) {
      Write-Host -ForegroundColor Red $Message
    }

    #If $ExitGracefully = True then run Log-Finish and exit script
    If ( $ExitGracefully -eq $True ){
      Edit-FileWait -Path $sFullPath -Scriptblock {
        Add-Content -Path $sFullPath -Value " "
      }
      Stop-Log -LogPath $LogPath
      Break
    }
  }
}

Function Stop-Log {
  <#
  .SYNOPSIS
    Write closing data to log file & exits the calling script

  .DESCRIPTION
    Writes finishing logging data to specified log file and then exits the calling script

  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to write finishing data to. Example: C:\Windows\Temp\Test_Script.log

  .PARAMETER NoExit
    Optional. If parameter specified, then the function will not exit the calling script, so that further execution can occur (like Send-Log)

  .PARAMETER ToScreen
    Optional. When parameter specified will display the content to screen as well as write to log file. This provides an additional
    another option to write content to screen as opposed to using debug mode.

  .INPUTS
    Parameters above

  .OUTPUTS
    None

  .NOTES
    Version:        1.0
    Author:         Luca Sturlese
    Creation Date:  10/05/12
    Purpose/Change: Initial function development.

    Version:        1.1
    Author:         Luca Sturlese
    Creation Date:  19/05/12
    Purpose/Change: Added debug mode support.

    Version:        1.2
    Author:         Luca Sturlese
    Creation Date:  01/08/12
    Purpose/Change: Added option to not exit calling script if required (via optional parameter).

    Version:        1.3
    Author:         Luca Sturlese
    Creation Date:  02/09/15
    Purpose/Change: Changed function name to use approved PowerShell Verbs. Improved help documentation.

    Version:        1.4
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Changed -NoExit parameter to switch type so no longer need to specify $True or $False (see example for info).

    Version:        1.5
    Author:         Luca Sturlese
    Creation Date:  12/09/15
    Purpose/Change: Added -ToScreen parameter which will display content to screen as well as write to the log file.

  .LINK
    http://9to5IT.com/powershell-logging-v2-easily-create-log-files

  .EXAMPLE
    Stop-Log -LogPath "C:\Windows\Temp\Test_Script.log"

    Writes the closing logging information to the log file and then exits the calling script.

    Note: If you don't specify the -NoExit parameter, then the script will exit the calling script.

  .EXAMPLE
    Stop-Log -LogPath "C:\Windows\Temp\Test_Script.log" -NoExit

    Writes the closing logging information to the log file but does not exit the calling script. This then
    allows you to continue executing additional functionality in the calling script (such as calling the
    Send-Log function to email the created log to users).
  #>

  [CmdletBinding()]

  Param (
    [Parameter(Mandatory=$true,Position=0)][string]$LogPath,
    [Parameter(Mandatory=$false,Position=1)][string]$LogName=((Get-WmiObject Win32_computerSystemproduct -Property UUID).UUID + ".log"),
    [Parameter(Mandatory=$false,Position=2)][switch]$NoExit,
    [Parameter(Mandatory=$false,Position=3)][switch]$ToScreen
  )

  Process {

    $sFullPath = Join-Path -Path $LogPath -ChildPath $LogName
    
    $script:sEndTime = (Get-Date).ToUniversalTime()
    $script:sNeededTime = $script:sEndTime - $script:sStartTime
    #Write-Host "$($script:sNeededTime.Hours)h:$($script:sNeededTime.Minutes)m:$($script:sNeededTime.Seconds)s:$($script:sNeededTime.Milliseconds)ms" -BackgroundColor Magenta
    $script:sNeededTimeStr =  "$($script:sNeededTime.Hours)h:$($script:sNeededTime.Minutes)m:$($script:sNeededTime.Seconds)s:$($script:sNeededTime.Milliseconds)ms"

$str = @"

***************************************************************************************************
Finished processing at [$((Get-Date).ToUniversalTime().ToString()) UTC]. Needed: $script:sNeededTimeStr
***************************************************************************************************
"@  
$str2 = @"
Finished processing at [$((Get-Date).ToUniversalTime().ToString()) UTC]. Needed: $script:sNeededTimeStr
"@   

    #Write to WinEventlog
    IF ($sEnableWinEventlog){
    Write-EventLog –LogName $sWinEventlog_Name –Source $sWinEventlog_Source –EntryType Information –EventID 2 –Message $str2
    }

    #Write to Logfile
    Edit-FileWait -Path $sFullPath -Scriptblock {

      Add-Content -Path $sFullPath -Value $str

      #Add-Content -Path $sFullPath -Value ""
      #Add-Content -Path $sFullPath -Value "***************************************************************************************************"
      #Add-Content -Path $sFullPath -Value ("Finished processing at [$((Get-Date).ToUniversalTime().ToString()) UTC]. Needed: " + $script:sNeededTimeStr)
      #Add-Content -Path $sFullPath -Value "***************************************************************************************************"
    }

    #Write to screen for debug mode
    Write-Debug ""
    Write-Debug "***************************************************************************************************"
    Write-Debug "Finished processing at [$((Get-Date).ToUniversalTime().ToString()) UTC]. Needed: $script:sNeededTimeStr"
    Write-Debug "***************************************************************************************************"

    #Write to scren for ToScreen mode
    If ( $ToScreen -eq $True ) {
      Write-Output ""
      Write-Output "***************************************************************************************************"
      Write-Output "Finished processing at [$((Get-Date).ToUniversalTime().ToString()) UTC]. Needed: $script:sNeededTimeStr" 
      Write-Output "***************************************************************************************************"
    }

    #Exit calling script if NoExit has not been specified or is set to False
    If( !($NoExit) -or ($NoExit -eq $False) ){
      Exit
    }
  }
}

Function Send-Log {
  <#
  .SYNOPSIS
    Emails completed log file to list of recipients

  .DESCRIPTION
    Emails the contents of the specified log file to a list of recipients

  .PARAMETER SMTPServer
    Mandatory. FQDN of the SMTP server used to send the email. Example: smtp.google.com

  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to email. Example: C:\Windows\Temp\Test_Script.log

  .PARAMETER EmailFrom
    Mandatory. The email addresses of who you want to send the email from. Example: "admin@9to5IT.com"

  .PARAMETER EmailTo
    Mandatory. The email addresses of where to send the email to. Seperate multiple emails by ",". Example: "admin@9to5IT.com, test@test.com"

  .PARAMETER EmailSubject
    Mandatory. The subject of the email you want to send. Example: "Cool Script - [" + (Get-Date).ToShortDateString() + "]"

  .INPUTS
    Parameters above

  .OUTPUTS
    Email sent to the list of addresses specified

  .NOTES
    Version:        1.0
    Author:         Luca Sturlese
    Creation Date:  05.10.12
    Purpose/Change: Initial function development.

    Version:        1.1
    Author:         Luca Sturlese
    Creation Date:  02/09/15
    Purpose/Change: Changed function name to use approved PowerShell Verbs. Improved help documentation.

    Version:        1.2
    Author:         Luca Sturlese
    Creation Date:  02/09/15
    Purpose/Change: Added SMTPServer parameter to pass SMTP server as oppposed to having to set it in the function manually.

  .LINK
    http://9to5IT.com/powershell-logging-v2-easily-create-log-files

  .EXAMPLE
    Send-Log -SMTPServer "smtp.google.com" -LogPath "C:\Windows\Temp\Test_Script.log" -EmailFrom "admin@9to5IT.com" -EmailTo "admin@9to5IT.com, test@test.com" -EmailSubject "Cool Script"

    Sends an email with the contents of the log file as the body of the email. Sends the email from admin@9to5IT.com and sends
    the email to admin@9to5IT.com and test@test.com email addresses. The email has the subject of Cool Script. The email is
    sent using the smtp.google.com SMTP server.
  #>

  [CmdletBinding()]

  Param (
    [Parameter(Mandatory=$true,Position=0)][string]$SMTPServer,
    [Parameter(Mandatory=$true,Position=1)][string]$LogPath,
    [Parameter(Mandatory=$true,Position=2)][string]$EmailFrom,
    [Parameter(Mandatory=$true,Position=3)][string]$EmailTo,
    [Parameter(Mandatory=$true,Position=4)][string]$EmailSubject
  )

  Process {
    Try {
      $sBody = ( Get-Content $LogPath | Out-String )

      #Create SMTP object and send email
      $oSmtp = new-object Net.Mail.SmtpClient( $SMTPServer )
      $oSmtp.Send( $EmailFrom, $EmailTo, $EmailSubject, $sBody )
      Exit 0
    }

    Catch {
      Exit 1
    }
  }
}

Function Test-FileLock {
<#
.SYNOPSIS
  Test if a files is locked by another Process.
.DESCRIPTION
  Test if a files is locked by another Process.
.EXAMPLE
  Example of how to use this cmdlet
.EXAMPLE
  Another example of how to use this cmdlet
.INPUTS
  Inputs to this cmdlet (if any)
.OUTPUTS
  Output from this cmdlet (if any)
.NOTES
  General notes
.COMPONENT
  The component this cmdlet belongs to
.ROLE
  The role this cmdlet belongs to
.FUNCTIONALITY
  The functionality that best describes this cmdlet
#>
  [CmdletBinding(DefaultParameterSetName='Parameter Set 1',
                 SupportsShouldProcess=$true,
                 PositionalBinding=$false,
                 HelpUri = 'http://www.microsoft.com/',
                 ConfirmImpact='Medium')]
  [Alias()]
  [OutputType([String])]
  Param (
    # Specifies a path to one or more locations.
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="Path",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to one or more locations.")]
    #[Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path,

    # Specifies a path to one or more locations. Unlike the Path parameter, the value of the LiteralPath parameter is
    # used exactly as it is typed. No characters are interpreted as wildcards. If the path includes escape characters,
    # enclose it in single quotation marks. Single quotation marks tell Windows PowerShell not to interpret any
    # characters as escape sequences.
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="LiteralPath",
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Literal path to one or more locations.")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $LiteralPath
  )
  
  begin {
  }
  
  process {
    if ($pscmdlet.ShouldProcess("Target", "Operation")) {
      # Modify [CmdletBinding()] to [CmdletBinding(SupportsShouldProcess=$true)]
      $paths = @()
      foreach ($aPath in $Path) {
        if (!(Test-Path -LiteralPath $aPath)) {
          $ex = New-Object System.Management.Automation.ItemNotFoundException "Cannot find path '$aPath' because it does not exist."
          $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
          $errRecord = New-Object System.Management.Automation.ErrorRecord $ex,'PathNotFound',$category,$aPath
          $psCmdlet.WriteError($errRecord)
          continue
        }
      
        # Resolve any relative paths
        $paths += $psCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($aPath)
      }
      
      foreach ($aPath in $paths) {
        if ($pscmdlet.ShouldProcess($aPath, 'Operation')) {
          # Process each path
          $oFile = New-Object System.IO.FileInfo $aPath
          
          try
          {
              $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
              if ($oStream)
              {
                $oStream.Close()
              }
              return $false
          }
          catch
          {
            # file is locked by a process.
            return $true
          }
          
        }
      }



    }
  }
  
  end {
  }
}

function Edit-FileWait {
<#
.SYNOPSIS
  Short description
.DESCRIPTION
  Long description
.EXAMPLE
  Example of how to use this cmdlet
.EXAMPLE
  Another example of how to use this cmdlet
.INPUTS
  Inputs to this cmdlet (if any)
.OUTPUTS
  Output from this cmdlet (if any)
.NOTES
  General notes
.COMPONENT
  The component this cmdlet belongs to
.ROLE
  The role this cmdlet belongs to
.FUNCTIONALITY
  The functionality that best describes this cmdlet
#>
  [CmdletBinding(DefaultParameterSetName='Parameter Set 1',
                 SupportsShouldProcess=$true,
                 PositionalBinding=$false,
                 HelpUri = 'http://www.microsoft.com/',
                 ConfirmImpact='Medium')]
  [Alias()]
  [OutputType([String])]
  Param (
    # Specifies a path to one or more locations.
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="Path",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to one or more locations.")]
    #[Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path,

    # Specifies a path to one or more locations. Unlike the Path parameter, the value of the LiteralPath parameter is
    # used exactly as it is typed. No characters are interpreted as wildcards. If the path includes escape characters,
    # enclose it in single quotation marks. Single quotation marks tell Windows PowerShell not to interpret any
    # characters as escape sequences.
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="LiteralPath",
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Literal path to one or more locations.")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $LiteralPath,

    [parameter(Mandatory)]
    [Object]
    $Scriptblock
  )
  
  begin {
    if ($pscmdlet.ShouldProcess("Target", "Operation")) {
      If ($PSBoundParameters['Scriptblock']) {
          If ($Scriptblock -isnot [scriptblock]) {
              $Scriptblock = [scriptblock]::Create($Scriptblock)
          } Else {
              $Scriptblock = [scriptblock]::Create( ($Scriptblock -replace '\$_','$Object'))
          }
      } 
    }
  }
  
  process {
    if ($pscmdlet.ShouldProcess("Target", "Operation")) {
      # Modify [CmdletBinding()] to [CmdletBinding(SupportsShouldProcess=$true)]
      $paths = @()
      foreach ($aPath in $Path) {
        if (!(Test-Path -LiteralPath $aPath)) {
          $ex = New-Object System.Management.Automation.ItemNotFoundException "Cannot find path '$aPath' because it does not exist."
          $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
          $errRecord = New-Object System.Management.Automation.ErrorRecord $ex,'PathNotFound',$category,$aPath
          $psCmdlet.WriteError($errRecord)
          continue
        }
      
        # Resolve any relative paths
        $paths += $psCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($aPath)
      }
      
      foreach ($aPath in $paths) {
        if ($pscmdlet.ShouldProcess($aPath, 'Operation')) {
          # Process each path
          
          DO {
            $skip = $false

            if (!(Test-FileLock -Path $aPath)) {
              $skip = $true
              
              # Insert write Actions here
              &$Scriptblock
              
            } else {
              Write-Debug ("File locked: " + $aPath + " Try again...")
              Start-Sleep -Milliseconds 100
            }
          } until ($skip -eq $true)
        }
      }
    }
  }
  
  end {
  }
}
