# Veeam AsBuilt Automated Deployment & Validation

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207+-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green)
![Repository](https://img.shields.io/badge/Repository-GitHub-black)
![Language](https://img.shields.io/badge/Language-PowerShell-blueviolet)
![Status](https://img.shields.io/badge/Status-Stable-success)
![Last Updated](https://img.shields.io/badge/Last%20Updated-2026--03--31-informational)

---

## 📌 Overview

Veeam AsBuilt Automated Deployment & Validation is a PowerShell automation script designed to validate the local environment, install or validate all required AsBuiltReport dependencies, handle online and offline module workflows, connect to Veeam Backup & Replication, generate the required report configuration file, and execute the Veeam AsBuilt report.

This project acts as a **wrapper and orchestration layer** for the official AsBuiltReport ecosystem, improving reliability, validation and execution experience in real-world environments.

---

## 🔗 Relationship with AsBuiltReport Project

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

### Important Notes

- The actual report generation logic is **fully handled by the official AsBuiltReport modules**
- This repository **does not contain or modify report templates or internal logic**
- All credits for report generation belong to the original AsBuiltReport contributors
- This script only **facilitates and standardizes execution in real-world environments**

---

## 🎯 Key Features

- Automated environment validation
- Online and offline module installation
- PowerShell compatibility handling
- Veeam connectivity validation
- Automatic JSON config generation
- Structured logging and summary
- Safe handling of unsupported versions

---

## ⚙️ Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Veeam Backup & Replication installed
- Administrative privileges

---

## 🚀 Usage

```powershell
.\vbr_asbuilt_v19_FULL.ps1
```

---

## 📂 Output

Default:

```
script_path\report
```

---

## ⚠️ Veeam v13 Limitation

The official AsBuiltReport module currently does not support Veeam v13.

---

## 📚 References

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

### Veeam Documentation

- Official Veeam Documentation  
  https://helpcenter.veeam.com/docs/backup/vsphere/

---

## 🧾 Attribution

This repository is an **independent automation layer** built on top of the AsBuiltReport ecosystem.

- All report generation logic belongs to the AsBuiltReport Project contributors
- This project does not modify or redistribute internal report logic
- It provides validation, orchestration and execution improvements

---

## ⚖️ Disclaimer

This project is not affiliated with or officially endorsed by:

- AsBuiltReport Project  
- Veeam Software  

All trademarks and product names are the property of their respective owners.

---

## 👨‍💻 Author

Juliano Cunha  
https://github.com/julianscunha

---

## 📄 License

MIT
