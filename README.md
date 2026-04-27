# Veeam AsBuilt Automated Deployment & Validation

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207+-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green)
![Repository](https://img.shields.io/badge/Repository-GitHub-black)
![Language](https://img.shields.io/badge/Language-PowerShell-blueviolet)
![Status](https://img.shields.io/badge/Status-Stable-success)
![Last Updated](https://img.shields.io/badge/Last%20Updated-2026--04--17-informational)

## Overview

Veeam AsBuilt Automated Deployment & Validation is a PowerShell automation script designed to validate the local environment, install or validate all required AsBuiltReport dependencies, handle online and offline module workflows, connect to Veeam Backup & Replication, generate the required report configuration file, and execute the Veeam AsBuilt report.

This project acts as a **wrapper and orchestration layer** for the official AsBuiltReport ecosystem, improving reliability, validation and execution experience in real-world environments.

The script was built to provide a guided and logged workflow for environments that may run in:
- Windows PowerShell 5.1
- PowerShell 7+
- online environments with PSGallery access
- offline environments using pre-staged modules
- Veeam Backup & Replication v12.x and v13.x validation scenarios

## Relationship with AsBuiltReport Project

This project does **not replace or modify** the official AsBuiltReport modules.

Instead, it acts as a **validation, orchestration and execution wrapper** around the original project.

### Purpose of this repository

This script was designed to:

- Validate environment prerequisites before execution
- Automate module installation (online and offline)
- Handle PowerShell compatibility scenarios (5.1 vs 7+)
- Ensure correct loading of Veeam PowerShell components
- Provide structured logging and execution summary
- Improve user experience and troubleshooting
- Prepare complete offline execution packages, including the NuGet provider

### Important Notes

- The actual report generation logic is **fully handled by the official AsBuiltReport modules**
- This repository **does not contain or modify report templates or internal logic**
- All credits for report generation belong to the original AsBuiltReport contributors
- This script only **facilitates and standardizes execution in real-world environments**

## Key Features

- Automated environment validation before report execution
- Online and offline module validation and installation workflow
- NuGet provider detection, export, promotion and validation
- PowerShellGet and PSGallery validation for online operations
- Automatic PowerShell 5.1 to PowerShell 7 relaunch when required by Veeam PowerShell components
- Validation of required module versions before execution
- Automatic report configuration JSON generation in the output directory
- Default output folder support (`script_path\report`)
- Structured logging with execution summary
- Clear handling of Veeam v13 limitations in the official AsBuiltReport.Veeam.VBR module
- Safer user experience with explicit prompts before major actions
- Dedicated `DownloadOnly` mode to prepare offline packages
- Network connectivity validation with controlled timeout before remote Veeam connection
- Intelligent Veeam connection handling
- Custom TCP connectivity validation with configurable timeout for improved execution predictability

## Requirements

- Windows Server 2016 or later
- Windows PowerShell 5.1 and/or PowerShell 7+
- Veeam Backup & Replication console/components installed on the execution host
- Administrative privileges
- Network connectivity to the target VBR server
- Internet access for online module installation, or pre-staged offline modules

## Installation

Clone the repository or download the script:

```powershell
git clone https://github.com/julianscunha/Veeam.VBR.ASBuilt.git
cd Veeam.VBR.ASBuilt
```

If required, allow local script execution:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

If PowerShell 7 is not installed, download and install it before using environments that require the Veeam PowerShell DLL loaded through .NET Core.

## Usage

Run the script with administrative privileges:

```powershell
.\vbr_asbuilt.ps1
```

### Supported execution modes

Interactive:
```powershell
.\vbr_asbuilt.ps1
```

Full execution mode:
```powershell
.\vbr_asbuilt.ps1 -Mode Full
```

Download required packages only:
```powershell
.\vbr_asbuilt.ps1 -Mode DownloadOnly
```

Full execution against a specific VBR server:
```powershell
.\vbr_asbuilt.ps1 -Mode Full -VBRServer localhost
```

Download modules to a custom offline path:
```powershell
.\vbr_asbuilt.ps1 -Mode DownloadOnly -ModulesPath "C:\Temp\modules"
```

Show built-in help:
```powershell
Get-Help .\vbr_asbuilt.ps1
Get-Help .\vbr_asbuilt.ps1 -Detailed
```

### Workflow Summary

1. Validate PowerShell version and execution context
2. Ask execution mode (`Full` or `DownloadOnly`)
3. Validate internet connectivity
4. Validate PowerShellGet / PSGallery for online operations
5. Validate or prepare the NuGet provider
6. Download required modules only **or** continue with full workflow
7. Validate required AsBuiltReport modules and versions
8. Install missing modules online or offline
9. Import modules in controlled dependency order
10. Validate and load Veeam PowerShell
11. Reuses existing sessions when available
12. Validates local execution without forcing a connection
13. Performs controlled remote connection with connectivity validation and credential prompt
14. Detect and validate the Veeam version
15. Prompt for output directory and generate the report JSON config
16. Execute the AsBuilt report
17. Write final summary to the log

## Parameters

The script supports the following parameters:

- `-Mode`  
  Defines the execution mode:
  - `Full`
  - `DownloadOnly`

- `-VBRServer`  
  Target Veeam Backup & Replication server. Default: `localhost`

- `-ModulesPath`  
  Path used to store or read offline modules. Default: `script_path\modules`

- `-OutputPath`  
  Directory used to store generated reports. Default: `script_path\report`

- `-SkipVersionPrompt`  
  Skips the confirmation prompt when Veeam v13+ is detected

## Interactive Prompts

Typical prompts include:

- `Opção [1/2]`
- `1 - Execução normal (validação + relatório)`
- `2 - Somente baixar pacotes`
- `Executar em PowerShell 7? (Y/N)`
- `Deseja continuar mesmo assim? (Y/N)` for Veeam v13+
- `Servidor [localhost]`
- `Diretório de saída [script_path\report]`
- `Criar diretório <path>? (Y/N)`

## Module Validation Baseline

The script validates these modules and minimum versions:

- PScribo `0.11.1`
- PScriboCharts `0.9.0`
- PSGraph `2.1.38.27`
- Diagrammer.Core `0.2.39`
- Veeam.Diagrammer `0.6.34` *(optional in some offline/runtime scenarios)*
- AsBuiltReport.Core `1.6.2`
- AsBuiltReport.Veeam.VBR `0.8.26`

Additionally, the script validates the NuGet provider with a minimum version of:

- NuGet provider `2.8.5.201`

## Online and Offline Module Handling

### Online Mode

If internet access is available, the script validates:
- PowerShellGet
- PSGallery trust configuration
- NuGet provider availability and minimum version

Then it attempts to install any missing or outdated modules directly from PSGallery.

### Download-Only Mode

If internet access is available, the script can run in `DownloadOnly` mode.

This mode downloads all required modules to the offline package folder without executing the report workflow.
In `DownloadOnly` mode, non-executed runtime stages are marked as `SKIPPED` in the final summary.

It also prepares the **NuGet provider** for offline use:
- if the local provider already meets the minimum version, it is exported to the offline package;
- if the local provider is below the minimum version, the script attempts to obtain a suitable provider in an isolated temporary session and then exports it to the offline package.

Example:

```powershell
.\vbr_asbuilt.ps1 -Mode DownloadOnly
```

Or with a custom destination:

```powershell
.\vbr_asbuilt.ps1 -Mode DownloadOnly -ModulesPath "C:\Temp\modules"
```

### Offline Mode

If internet access is unavailable, the script looks for modules in:

```text
script_path\modules
```

Expected structure:

```text
script_path\modules\AsBuiltReport.Core\1.6.2\...
script_path\modules\AsBuiltReport.Veeam.VBR\0.8.26\...
script_path\modules\PScribo\0.11.1\...
script_path\modules\PScriboCharts\0.9.0\...
script_path\modules\PSGraph\2.1.38.27\...
script_path\modules\Diagrammer.Core\0.2.39\...
script_path\modules\Veeam.Diagrammer\0.6.34\...
script_path\modules\NuGet\2.8.5.208\...
```

For the NuGet provider, the script promotes the offline package to the standard PackageManagement discovery locations, such as:

```text
%LOCALAPPDATA%\PackageManagement\ProviderAssemblies\NuGet\<version>\
C:\Program Files\PackageManagement\ProviderAssemblies\NuGet\<version>\
```

Success is accepted when the provider is recognized by the system after promotion, even if only one of the target locations is writable.

If offline modules are not found, the script provides ready-to-run commands for a helper machine with internet access, for example:

```powershell
Save-Module -Name PScribo -RequiredVersion 0.11.1 -Path ".\modules"
Save-Module -Name PScriboCharts -RequiredVersion 0.9.0 -Path ".\modules"
Save-Module -Name PSGraph -RequiredVersion 2.1.38.27 -Path ".\modules"
Save-Module -Name Diagrammer.Core -RequiredVersion 0.2.39 -Path ".\modules"
Save-Module -Name Veeam.Diagrammer -RequiredVersion 0.6.34 -Path ".\modules"
Save-Module -Name AsBuiltReport.Core -RequiredVersion 1.6.2 -Path ".\modules"
Save-Module -Name AsBuiltReport.Veeam.VBR -RequiredVersion 0.8.26 -Path ".\modules"
```

The offline package should also contain:

```text
.\modules\NuGet\<version>\...
```

## Veeam Connection Behavior

The script implements intelligent connection handling:

- If an active Veeam session exists, it is reused
- When running locally on the Veeam server, the script validates access without forcing a new connection
- When running remotely, the script:
  - validates network connectivity to port 9392
  - prompts for credentials
  - establishes a controlled connection using `Connect-VBRServer`
- Connection success is always validated before continuing execution

## Veeam Version Handling

The script detects the VBR version from `Get-VBRBackupServerInfo`.

Behavior:
- VBR lower than v12: execution is blocked
- VBR v12.x: execution continues normally
- VBR v13.x: the script warns the user because the official report module does not support VBR v13

## Output & Logging

Default output folder:

```text
script_path\report
```

Generated artifacts may include:
- Word report
- HTML report
- `AsBuiltReport.Veeam.VBR.json`
- execution log (`AsBuiltReport_Veeam.log`)

The console is intentionally reduced to:
- INFO
- WARN
- ERROR

The log file stores full details, including:
- SUCCESS
- DEBUG
- module paths
- provider paths
- version validation
- final execution summary

Example summary block:

```text
===== RESUMO FINAL =====
PowerShell: OK
Connectivity: OK
NuGetGallery: OK
Modules: OK
VeeamPowerShell: OK
VeeamConnection: OK
VeeamVersion: WARNING
ReportConfig: OK
ReportExecution: FAILED
FinalStatus: FAILED
```

In `DownloadOnly` mode, non-executed runtime stages are marked as `SKIPPED` in the final summary.

## Error Handling & Troubleshooting

- If the Veeam DLL fails in Windows PowerShell 5.1, allow the script to relaunch in PowerShell 7
- If module installation fails online, verify internet access, NuGet provider status, and PSGallery reachability
- If offline mode is required, confirm that the `modules` folder is next to the script and follows the expected versioned structure
- If you only want to prepare offline packages, use `-Mode DownloadOnly`
- If `AsBuiltReport.Veeam.VBR.json` is missing, the script attempts to create it automatically in the output folder
- If the report fails on Veeam v13, this is expected behavior from the current official AsBuiltReport.Veeam.VBR module
- If the NuGet provider is not recognized offline, verify the contents of `modules\NuGet\<version>` and confirm that promotion to `ProviderAssemblies` succeeded
- Use `Get-Help .\vbr_asbuilt.ps1 -Detailed` to view full parameter documentation

## Limitations

- The official `AsBuiltReport.Veeam.VBR` report currently does not support Veeam Backup & Replication v13
- The script is interactive by design
- The script assumes the Veeam console components are installed and available on the execution host
- Some modules behave differently between Windows PowerShell Desktop and PowerShell 7
- `Veeam.Diagrammer` may be skipped in some offline/runtime scenarios without blocking the main report workflow
- Full offline execution still depends on the behavior of the official AsBuiltReport modules and their interaction with PowerShellGet/PackageManagement in the local environment
- Interactive prompts may appear in Portuguese depending on the script configuration.

## Security Considerations

- Run with least privilege required for the task
- Restrict access to logs and generated reports
- Do not store plaintext credentials
- Use a controlled test environment before production rollout

## Contributing

1. Fork the repository
2. Create a branch: `git checkout -b feature/your-feature`
3. Commit your changes
4. Push the branch
5. Open a pull request

## References

This project relies on the official AsBuiltReport ecosystem and related PowerShell modules.

### Official AsBuiltReport Project

- AsBuiltReport Organization  
  https://github.com/AsBuiltReport

### Core Framework

- AsBuiltReport.Core  
  https://github.com/AsBuiltReport/AsBuiltReport.Core

### Veeam Report Module

- AsBuiltReport.Veeam.VBR  
  https://github.com/AsBuiltReport/AsBuiltReport.Veeam.VBR

### PowerShell Gallery

Modules are distributed via PSGallery:

- https://www.powershellgallery.com/packages/AsBuiltReport.Core  
- https://www.powershellgallery.com/packages/AsBuiltReport.Veeam.VBR  

### PackageManagement / NuGet Provider

- https://learn.microsoft.com/powershell/module/packagemanagement/install-packageprovider
- https://learn.microsoft.com/powershell/module/packagemanagement/get-packageprovider
- https://stackoverflow.com/questions/51406685/how-do-i-install-the-nuget-provider-for-powershell-on-a-unconnected-machine-so-i

### Veeam Documentation

- Official Veeam Documentation  
  https://helpcenter.veeam.com/docs/backup/vsphere/

## Attribution

This repository is an **independent automation layer** built on top of the AsBuiltReport ecosystem.

- All report generation logic belongs to the AsBuiltReport Project contributors
- This project does not modify or redistribute internal report logic
- It provides validation, orchestration and execution improvements

## Disclaimer

This project is not affiliated with or officially endorsed by:

- AsBuiltReport Project  
- Veeam Software  

All trademarks and product names are the property of their respective owners.

## License

MIT — see the LICENSE file
